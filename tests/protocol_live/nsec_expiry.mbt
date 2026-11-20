///|
// Build a small valid response using the existing uncompressed RR encoder.
fn expiry_response(
  answers : Array[@wire.Record],
  additional : Array[@wire.Record],
) -> Bytes raise {
  let bytes = b"\x00\x00\x84\x00\x00\x00\x00\x00\x00\x00\x00\x00".to_array()
  bytes[7] = answers.length().to_byte()
  bytes[11] = additional.length().to_byte()
  for section in [answers, additional] {
    for record in section {
      let query = @wire.query_with_answers(record.name, record.rr_type, [record])
      let start = 16 + record.name.to_wire().length()
      for i in start..<query.length() {
        bytes.push(query[i])
      }
    }
  }
  Bytes::makei(bytes.length(), i => bytes[i])
}

///|
fn nsec_expiry_checks(ip : UInt32) -> Json raise {
  let sender = @native.MulticastSocket::open(ip)
  defer sender.close()
  let browser = @native.Browser::open(ip)
  defer browser.close()
  let start = @native.monotonic_ms()
  let instance = @model.DnsName::parse("p\{start}._mdexpiry._tcp.local.")
  let host = @model.DnsName::parse("p\{start}-expiry.local.")
  let srv : @wire.Record = {
    name: instance,
    rr_type: 33,
    rr_class: 1,
    ttl: 120U,
    cache_flush: false,
    data: @wire.Srv(0, 0, 18421, host),
    section: @wire.Answer,
  }
  let addr : @wire.Record = {
    ..srv,
    name: host,
    rr_type: 1,
    data: @wire.A(b"\xc0\x00\x02\x01"),
  }
  let nsec : @wire.Record = {
    ..addr,
    rr_type: 47,
    ttl: 1U,
    data: @wire.Nsec(host, b"\x40"),
  }
  // Prime the Browser with SRV/A and an Additional NSEC before it has
  // scheduled an address query. Poll this Browser using its actual clock.
  let initial = expiry_response([srv], [addr, nsec])
  let _ = browser.resolve(instance, timeout_ms=6000)
  let sent_at = @native.monotonic_ms()
  sender.send(initial)
  let mut saw_negative = false
  let mut resumed_at = -1L
  let mut published = false
  while @native.monotonic_ms() - sent_at < 4500L {
    let _ = browser.poll(timeout_ms=15)
    let negative = browser.is_negative(host, 28)
    if negative {
      saw_negative = true
    }
    if sender.receive(timeout_ms=5) is Some(datagram) {
      let packet = @probe.independent_packet(datagram.bytes) catch {
        _ => continue
      }
      if (packet.flags & 0x8000) == 0 &&
        packet.questions.any(q => {
          q.rr_type == 28 && q.name == host.to_presentation()
        }) {
        guard saw_negative && !negative else {
          fail("AAAA queried while negative evidence was effective")
        }
        if !published {
          resumed_at = @native.monotonic_ms() - sent_at
          guard resumed_at >= 1000L else {
            fail("AAAA query resumed before the one-second TTL")
          }
          let ipv6 : @wire.Record = {
            ..addr,
            rr_type: 28,
            data: @wire.Aaaa(
              b"\x20\x01\x0d\xb8\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x01",
            ),
          }
          sender.send(expiry_response([ipv6], []))
          published = true
        }
      }
    }
    if published &&
      browser.snapshots().any(s => s.addresses.any(a => a.length() == 16)) {
      return {
        "passed": true,
        "ttl_seconds": 1,
        "first_aaaa_ms_after_send": resumed_at,
        "additional_nsec_admitted": true,
        "positive_after_query": true,
        "limits": "same-host IPv4 multicast, controlled fixture, independent outgoing question parser",
      }
    }
  }
  fail("timed out waiting for negative expiry and the subsequent AAAA result")
}
