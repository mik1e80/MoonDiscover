///|
fn main raise {
  let args = @env.args()
  guard args.length() == 3 else {
    fail("usage: security_fuzz <UInt32 seed> <cases 1..10000>")
  }
  let initial = @string.parse_uint(args[1])
  let count = @string.parse_int(args[2])
  guard count > 0 && count <= 10000 else {
    fail("case budget outside 1..10000")
  }
  let mut state = initial
  fn random(n : Int32) -> Int32 {
    state = state * 1664525U + 1013904223U
    (state % n.reinterpret_as_uint()).reinterpret_as_int()
  }
  let service = @model.DnsName::parse("_fuzz._tcp.local.")
  let instance = @model.DnsName::parse("fixture._fuzz._tcp.local.")
  let host = @model.DnsName::parse("fixture.local.")
  let records : Array[@wire.Record] = [
    {
      name: service,
      rr_type: 12,
      rr_class: 1,
      cache_flush: false,
      ttl: 120U,
      data: @wire.Ptr(instance),
      section: @wire.Answer,
    },
    {
      name: instance,
      rr_type: 33,
      rr_class: 1,
      cache_flush: true,
      ttl: 120U,
      data: @wire.Srv(65535, 65535, 65535, host),
      section: @wire.Answer,
    },
    {
      name: instance,
      rr_type: 16,
      rr_class: 1,
      cache_flush: true,
      ttl: 120U,
      data: @wire.Txt(
        @model.TxtRecord::from_entries([
          b"flag",
          b"empty=",
          b"dup=first",
          b"dup=last",
          Bytes::make(255, b'x'),
        ]),
      ),
      section: @wire.Answer,
    },
    {
      name: host,
      rr_type: 1,
      rr_class: 1,
      cache_flush: true,
      ttl: 4294967295U,
      data: @wire.A(b"\x0a\x00\x00\x01"),
      section: @wire.Answer,
    },
    {
      name: host,
      rr_type: 28,
      rr_class: 1,
      cache_flush: true,
      ttl: 120U,
      data: @wire.Aaaa(Bytes::make(16, b'\xff')),
      section: @wire.Answer,
    },
  ]
  let corpus = records.map(record => {
    let raw = @wire.query_with_answers(record.name, record.rr_type, [record]).to_array()
    raw[2] = b'\x84'
    Bytes::makei(raw.length(), i => raw[i])
  })
  let mut rejected = 0
  for i in 0..<count {
    let source = corpus[random(corpus.length())]
    let mutation = random(5)
    let raw = source.to_array()
    match mutation {
      0 => raw[random(raw.length())] = random(256).to_byte()
      1 => {
        raw[4] = b'\xff'
        raw[5] = b'\xff'
      }
      2 => {
        raw[12] = b'\xc0'
        raw[13] = b'\x0c'
      }
      3 =>
        for _ in 0..<(random(8) + 1) {
          let _ = raw.pop()
        }
      _ => {
        raw[0] = random(256).to_byte()
        raw[3] = random(256).to_byte()
      }
    }
    let packet = Bytes::makei(raw.length(), i => raw[i])
    // Emit before risky code. The runner persists the last received case; if
    // stdout was buffered at a crash, replay the saved seed through that run.
    println(
      Json::object({
        "case": Json(i),
        "seed": Json(initial),
        "packet_hex": Json(@model.bytes_hex(packet)),
      }).stringify(),
    )
    let engine = @engine.Engine::new(
      cache_capacity=8,
      service_capacity=2,
      event_capacity=4,
      query_capacity=4,
    )
    let _ = engine.browse(service, "fuzz", 0)
    engine.ingest_message(
      { id: 0, flags: 0x8400, questions: [], records, },
      "fuzz",
      0,
    )
    let before = engine.snapshots().map(@replay.snapshot_json)
    engine.ingest(packet, "fuzz", 0) catch {
      _ => {
        rejected += 1
        assert_eq(engine.snapshots().map(@replay.snapshot_json), before)
        assert_eq(engine.stats().cached_records, 5)
        engine.ingest_message(
          { id: 0, flags: 0x8400, questions: [], records, },
          "fuzz",
          0,
        )
        assert_true(engine.snapshots()[0].complete)
      }
    }
    let stats = engine.stats()
    assert_true(
      stats.cached_records <= 8 &&
      stats.services <= 2 &&
      stats.query_jobs <= 4 &&
      stats.queued_events <= 4,
    )
    engine.close()
    assert_eq(
      engine.stats().cached_records +
      engine.stats().services +
      engine.stats().subscriptions,
      0,
    )
    let replay = @replay.Replay::new(max_frames=4, max_output_events=16)
    let invalid = [
        "{\"kind\":\"advance\",\"at_ms\":0,\"at_ms\":1}", "{\"kind\":\"advance\",\"at_ms\":-1}",
        "{\"kind\":\"advance\",\"at_ms\":0.5}", "{\"kind\":\"packet\",\"at_ms\":0,\"scope\":\"fuzz\",\"packet_hex\":\"xx\"}",
      ][random(4)]
    assert_true(
      try {
        let _ = replay.step_line(invalid)
        false
      } catch {
        _ => true
      },
    )
    assert_true(
      replay.step_line("{\"kind\":\"advance\",\"at_ms\":0}").is_empty(),
    )
  }
  println(
    Json::object({
      "passed": Json(true),
      "seed": Json(initial),
      "cases": Json(count),
      "rejected_packets": Json(rejected),
    }).stringify(),
  )
}
