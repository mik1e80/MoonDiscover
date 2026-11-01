///|
fn transmit(
  sender : @native.MulticastSocket,
  receiver : @native.MulticastSocket,
  bytes : Bytes,
) -> @probe.ProbePacket raise {
  sender.send(bytes)
  let deadline = @native.monotonic_ms() + 3000L
  while @native.monotonic_ms() < deadline {
    if receiver.receive(timeout_ms=50) is Some(packet) && packet.bytes == bytes {
      guard packet.source_port == 5353 &&
        packet.interface_index == receiver.interface_index &&
        packet.destination_ipv4 == 0xe00000fbU else {
        fail("wrong UDP metadata")
      }
      return @probe.independent_packet(packet.bytes)
    }
  }
  fail("multicast loopback did not deliver the transmitted query")
}

///|
fn packet_checks(ip : UInt32) -> Json raise {
  let sender = @native.MulticastSocket::open(ip)
  defer sender.close()
  let receiver = @native.MulticastSocket::open(ip)
  defer receiver.close()
  let service = @dnssd.DnsName::parse("_full-probe._tcp.local.")
  let (engine, _) = @probe.populated(service)
  defer engine.close()
  let raw : Array[Json] = []
  let mut answers = 0
  let mut packets = 0
  for ;; {
    guard engine.poll_outbound() is Some(outbound) else {
      fail("missing UDP burst")
    }
    let packet = transmit(sender, receiver, outbound.bytes)
    raw.push(Json(@model.bytes_hex(outbound.bytes)))
    let pending = engine.stats().queued_datagrams > 0
    guard (packet.flags & 0x0200) == (if pending { 0x0200 } else { 0 }) else {
      fail("UDP TC chain")
    }
    if packets == 0 {
      guard packet.questions.length() == 1 &&
        packet.questions[0].name == service.to_presentation() &&
        packet.questions[0].rr_type == 12 &&
        packet.questions[0].rr_class == 1 else {
        fail("UDP first question")
      }
    } else {
      guard packet.questions.is_empty() else {
        fail("UDP continuation question")
      }
    }
    for answer in packet.answers {
      guard answer.owner == service.to_presentation() &&
        answer.target == "p\{answers}-probe." + service.to_presentation() &&
        answer.rr_type == 12 &&
        answer.rr_class == 1 else {
        fail("UDP Known Answer content/order")
      }
      answers += 1
    }
    packets += 1
    if !pending {
      break
    }
  }
  guard answers == 260 && packets > 1 else { fail("UDP burst lost answers") }
  let cancelled_service = @dnssd.DnsName::parse("_cancel-probe._tcp.local.")
  let (cancelled, id) = @probe.populated(cancelled_service)
  defer cancelled.close()
  guard cancelled.poll_outbound() is Some(head) else {
    fail("missing cancellation head")
  }
  let _ = transmit(sender, receiver, head.bytes)
  let tails = cancelled.stats().queued_datagrams
  guard tails > 0 else { fail("no pending cancellation tail") }
  cancelled.cancel(id, 120)
  guard cancelled.stats().queued_datagrams == 0 &&
    cancelled.poll_outbound() is None else {
    fail("cancel left pending UDP work")
  }
  let quiet_until = @native.monotonic_ms() + 250L
  while @native.monotonic_ms() < quiet_until {
    if receiver.receive(timeout_ms=20) is Some(datagram) {
      if datagram.bytes.length() < 12 ||
        (datagram.bytes[2].to_int() & 0x80) != 0 {
        continue
      }
      let parsed = @probe.independent_packet(datagram.bytes) catch {
        _ => continue
      }
      guard !parsed.answers.any(a => {
          a.owner == cancelled_service.to_presentation()
        }) &&
        !parsed.questions.any(q => q.name == cancelled_service.to_presentation()) else {
        fail("cancelled query reached UDP receiver")
      }
    }
  }
  let oversized = @dnssd.Engine::new(seed=11U)
  defer oversized.close()
  let instance = @dnssd.DnsName::parse("big._large-probe._tcp.local.")
  let _ = oversized.resolve(instance, "protocol-probe", 0)
  oversized.ingest_message(
    {
      id: 0,
      flags: 0x8400,
      questions: [],
      records: [
        {
          name: instance,
          rr_type: 16,
          rr_class: 1,
          ttl: 120U,
          cache_flush: false,
          section: @dnssd.Section::Answer,
          data: @dnssd.RData::Txt(
            @dnssd.TxtRecord::from_entries(
              Array::make(36, Bytes::make(250, b'x')),
            ),
          ),
        },
      ],
    },
    "protocol-probe",
    0,
  )
  oversized.advance(120)
  let mut fallback = false
  while oversized.poll_outbound() is Some(outbound) {
    if outbound.rr_type == 16 {
      let parsed = transmit(sender, receiver, outbound.bytes)
      guard parsed.answers.is_empty() &&
        parsed.questions.length() == 1 &&
        parsed.questions[0].name == instance.to_presentation() &&
        parsed.questions[0].rr_type == 16 &&
        parsed.flags == 0 else {
        fail("invalid plain QM UDP fallback")
      }
      fallback = true
    }
  }
  let mut diagnostic = false
  while oversized.poll_event() is Some(event) {
    if event is @dnssd.Event::Diagnostic("known_answer_limit", _) {
      diagnostic = true
    }
  }
  guard fallback && diagnostic else {
    fail("UDP fallback missing query or diagnostic")
  }
  Json::object({
    "passed": Json(true),
    "transport": Json("IPv4 multicast UDP with receive metadata"),
    "independent_parser": Json(true),
    "known_answers": Json(answers),
    "datagrams": Json(packets),
    "cancelled_pending_tails": Json(tails),
    "cancellation_quiet_ms": Json(250),
    "plain_qm_fallback": Json(true),
    "datagrams_hex": Json::array(raw),
  })
}
