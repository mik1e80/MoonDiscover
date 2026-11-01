///|
/// Test-only decoder for the exact uncompressed mDNS query subset emitted here.
/// It deliberately does not call the production wire decoder.
struct ProbeQuestion {
  name : String
  rr_type : Int32
  rr_class : Int32
}

///|
struct ProbeAnswer {
  owner : String
  rr_type : Int32
  rr_class : Int32
  target : String
}

///|
struct ProbePacket {
  flags : Int32
  questions : Array[ProbeQuestion]
  answers : Array[ProbeAnswer]
}

///|
fn read_u16(bytes : Bytes, position : Int32) -> Int32 raise {
  guard position >= 0 && position + 2 <= bytes.length() else {
    fail("truncated 16-bit field")
  }
  (bytes[position].to_int() << 8) | bytes[position + 1].to_int()
}

///|
fn independent_name(bytes : Bytes, start : Int32) -> (String, Int32) raise {
  let labels : Array[String] = []
  let mut position = start
  for ;; {
    guard position < bytes.length() else { fail("truncated DNS name") }
    let length = bytes[position].to_int()
    position += 1
    if length == 0 {
      break
    }
    guard length <= 63 &&
      (length & 0xC0) == 0 &&
      position + length <= bytes.length() else {
      fail("invalid or compressed test name")
    }
    let label = StringBuilder()
    for i in position..<(position + length) {
      label.write_char(bytes[i].to_int().unsafe_to_char())
    }
    labels.push(label.to_string())
    position += length
  }
  guard !labels.is_empty() else { fail("root name is not expected") }
  let result = StringBuilder()
  for i, label in labels {
    if i > 0 {
      result.write_char('.')
    }
    result.write_string(label)
  }
  result.write_char('.')
  (result.to_string(), position)
}

///|
fn independent_packet(bytes : Bytes) -> ProbePacket raise {
  guard bytes.length() >= 12 && bytes.length() <= 9000 else {
    fail("invalid DNS datagram length")
  }
  let flags = read_u16(bytes, 2)
  let question_count = read_u16(bytes, 4)
  let answer_count = read_u16(bytes, 6)
  guard read_u16(bytes, 8) == 0 && read_u16(bytes, 10) == 0 else {
    fail("unexpected authority or additional records")
  }
  let questions : Array[ProbeQuestion] = []
  let answers : Array[ProbeAnswer] = []
  let mut position = 12
  for _ in 0..<question_count {
    let (name, next) = independent_name(bytes, position)
    guard next + 4 <= bytes.length() else { fail("truncated question") }
    questions.push({
      name,
      rr_type: read_u16(bytes, next),
      rr_class: read_u16(bytes, next + 2),
    })
    position = next + 4
  }
  for _ in 0..<answer_count {
    let (owner, next) = independent_name(bytes, position)
    guard next + 10 <= bytes.length() else { fail("truncated answer header") }
    let rr_type = read_u16(bytes, next)
    let rr_class = read_u16(bytes, next + 2)
    let data_length = read_u16(bytes, next + 8)
    let data_start = next + 10
    let data_end = data_start + data_length
    guard data_end <= bytes.length() else { fail("truncated RDATA") }
    guard rr_type == 12 else { fail("unexpected answer type") }
    let (target, target_end) = independent_name(bytes, data_start)
    guard target_end == data_end else { fail("PTR RDATA length mismatch") }
    answers.push({ owner, rr_type, rr_class, target, })
    position = data_end
  }
  guard position == bytes.length() else { fail("unparsed trailing bytes") }
  { flags, questions, answers, }
}

///|
fn populated(service : @model.DnsName) -> (@engine.Engine, Int32) raise {
  let engine = @engine.Engine::new(
    event_capacity=1024,
    query_capacity=2048,
    seed=11U,
  )
  let id = engine.browse(service, "protocol-probe", 0)
  for batch in 0..<3 {
    let records : Array[@wire.Record] = []
    for i in (batch * 128)..<((batch + 1) * 128).min(260) {
      records.push({
        name: service,
        rr_type: 12,
        rr_class: 1,
        ttl: 120U,
        cache_flush: false,
        data: @wire.Ptr(
          @model.DnsName::parse("p\{i}-probe." + service.to_presentation()),
        ),
        section: @wire.Answer,
      })
    }
    engine.ingest_message(
      { id: 0, flags: 0x8400, questions: [], records, },
      "protocol-probe",
      0,
    )
  }
  engine.advance(120)
  (engine, id)
}

///|
fn collect_burst(engine : @engine.Engine) -> Array[ProbePacket] raise {
  let packets : Array[ProbePacket] = []
  guard engine.poll_outbound() is Some(first) else {
    fail("missing first Known Answer packet")
  }
  packets.push(independent_packet(first.bytes))
  while engine.stats().queued_datagrams > 0 {
    guard engine.poll_outbound() is Some(continuation) else {
      fail("missing Known Answer continuation")
    }
    packets.push(independent_packet(continuation.bytes))
  }
  packets
}

///|
fn check_full_burst() -> Int32 raise {
  let service = @model.DnsName::parse("_full._tcp.local.")
  let (engine, _) = populated(service)
  defer engine.close()
  let packets = collect_burst(engine)
  guard packets.length() > 1 else { fail("expected a multi-packet burst") }
  let mut seen = 0
  for i, packet in packets {
    guard (packet.flags & 0x0200) ==
      (if i + 1 < packets.length() { 0x0200 } else { 0 }) else {
      fail("TC bit does not match burst position")
    }
    if i == 0 {
      guard packet.questions.length() == 1 else {
        fail("first packet must carry one question")
      }
      let question = packet.questions[0]
      guard question.name == service.to_presentation() &&
        question.rr_type == 12 &&
        question.rr_class == 1 else {
        fail("first question does not match service browse")
      }
    } else {
      guard packet.questions.is_empty() else {
        fail("continuation packet must not repeat the question")
      }
    }
    for answer in packet.answers {
      let expected = "p\{seen}-probe." + service.to_presentation()
      guard answer.owner == service.to_presentation() &&
        answer.rr_type == 12 &&
        answer.rr_class == 1 &&
        answer.target == expected else {
        fail("Known Answer was malformed, duplicated, or out of order")
      }
      seen += 1
    }
  }
  guard seen == 260 else { fail("burst did not carry all 260 answers") }
  seen
}

///|
fn check_cancellation() -> Int32 raise {
  let service = @model.DnsName::parse("_cancel._tcp.local.")
  let (engine, id) = populated(service)
  defer engine.close()
  guard engine.poll_outbound() is Some(head) else {
    fail("missing cancellation head")
  }
  let parsed = independent_packet(head.bytes)
  guard (parsed.flags & 0x0200) == 0x0200 && engine.stats().queued_datagrams > 0 else {
    fail("cancellation setup did not create a pending tail")
  }
  let pending = engine.stats().queued_datagrams
  engine.cancel(id, 120)
  guard engine.stats().queued_datagrams == 0 && engine.poll_outbound() is None else {
    fail("cancelled subscription left a tail packet")
  }
  pending
}

///|
fn check_oversize_fallback() -> Unit raise {
  let engine = @engine.Engine::new(seed=11U)
  defer engine.close()
  let instance = @model.DnsName::parse("big._large._tcp.local.")
  let _ = engine.resolve(instance, "protocol-probe", 0)
  let txt = @model.TxtRecord::from_entries(
    Array::make(36, Bytes::make(250, b'x')),
  )
  engine.ingest_message(
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
          data: @wire.Txt(txt),
          section: @wire.Answer,
        },
      ],
    },
    "protocol-probe",
    0,
  )
  engine.advance(120)
  let mut fallback : ProbePacket? = None
  while engine.poll_outbound() is Some(outbound) {
    if outbound.rr_type == 16 {
      fallback = Some(independent_packet(outbound.bytes))
    }
  }
  guard fallback is Some(packet) else {
    fail("oversized Known Answer did not produce a TXT query")
  }
  guard (packet.flags & 0x0200) == 0 &&
    packet.questions.length() == 1 &&
    packet.questions[0].name == instance.to_presentation() &&
    packet.questions[0].rr_type == 16 &&
    packet.questions[0].rr_class == 1 &&
    packet.answers.is_empty() else {
    fail("fallback is not a plain QM TXT query")
  }
  let mut diagnosed = false
  while engine.poll_event() is Some(event) {
    if event is @engine.Diagnostic("known_answer_limit", _) {
      diagnosed = true
    }
  }
  guard diagnosed else { fail("oversize fallback diagnostic was lost") }
}

///|
test "smoke: independent parser validates emitted Known-Answer packets" {
  assert_eq(check_full_burst(), 260)
  assert_true(check_cancellation() > 0)
  check_oversize_fallback()
}
