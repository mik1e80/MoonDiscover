///|
test "smoke: same-scope peer QM defers a question once, preserving eventual send" {
  let records = fixture()
  let engine = @engine.Engine::new()
  let _ = engine.browse(records[0].name, "first", 0)
  let _ = engine.browse(records[0].name, "second", 0)
  let peer = @wire.qm_query(records[0].name, 12)
  engine.ingest(peer, "first", 1)
  engine.advance(120)
  assert_eq(engine.poll_outbound().unwrap().scope, "second")
  assert_true(engine.poll_outbound() is None)
  for now in [500L, 950L, 1001L] {
    engine.ingest(peer, "first", now)
  }
  assert_eq(engine.poll_outbound().unwrap().scope, "first")
  assert_true(engine.snapshots().is_empty())
}

///|
test "smoke: peer Known Answers must be a valid subset and are never cached" {
  let records = fixture()
  let ptr = records[0]
  let cached : @wire.Record = { ..ptr, ttl: 120U, }
  for variant in 0..<4 {
    let engine = @engine.Engine::new()
    let _ = engine.browse(ptr.name, "link", 0)
    engine.ingest_message(message([cached]), "link", 0)
    let foreign = @model.DnsName::parse("other._http._tcp.local.")
    let ka = match variant {
      1 => { ..cached, data: @wire.Ptr(foreign), }
      2 => { ..cached, ttl: 121U, }
      _ => { ..cached, ttl: 119U, }
    }
    let peer = @wire.decode(@wire.query_with_answers(ptr.name, 12, [ka]))
    let flags = if variant == 3 { 0x0200 } else { 0 }
    engine.ingest_message({ ..peer, flags, }, "link", 1)
    engine.advance(120)
    let mut sent_ptr = false
    while engine.poll_outbound() is Some(query) {
      if query.rr_type == 12 {
        sent_ptr = true
      }
    }
    assert_eq(sent_ptr, variant != 0)
    assert_eq(engine.snapshots().length(), 1)
    assert_eq(engine.snapshots()[0].remaining_ttl_ms, 119880L)
  }
}
