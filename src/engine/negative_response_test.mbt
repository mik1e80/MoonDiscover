///|
test "smoke: NSEC Additional suppresses only AAAA until expiry and positive recovery" {
  let records = fixture()
  let host = records[3].name
  let engine = @engine.Engine::new()
  let _ = engine.browse(records[0].name, "link", 0)
  let nsec : @wire.Record = {
    name: host,
    rr_type: 47,
    rr_class: 1,
    cache_flush: true,
    ttl: 2U,
    data: @wire.Nsec(host, b"\x40"),
    section: @wire.Additional,
  }
  let input = records.copy()
  input.push(nsec)
  engine.ingest_message(message(input), "link", 0)
  assert_true(engine.snapshots()[0].complete)
  assert_true(engine.is_negative("link", host, 28))
  engine.advance(120)
  while engine.poll_outbound() is Some(q) {
    assert_true(q.rr_type != 28)
  }
  engine.advance(2000)
  assert_false(engine.is_negative("link", host, 28))
  engine.advance(2120)
  let mut resumed = false
  while engine.poll_outbound() is Some(q) {
    if q.rr_type == 28 {
      resumed = true
    }
  }
  assert_true(resumed)
  engine.ingest_message(message([{ ..nsec, ttl: 120U, }]), "link", 2200)
  assert_true(engine.is_negative("link", host, 28))
  engine.ingest_message(
    message([
      { ..records[3], rr_type: 28, data: @wire.Aaaa(Bytes::make(16, 1)), },
    ]),
    "link",
    2300,
  )
  assert_false(engine.is_negative("link", host, 28))
  assert_eq(engine.snapshots()[0].addresses.length(), 2)
  engine.close()
  assert_false(engine.is_negative("link", host, 28))
}

///|
test "smoke: negative SRV and TXT keep resolution partial and shared PTR continues" {
  let records = fixture()
  let engine = @engine.Engine::new()
  let _ = engine.browse(records[0].name, "link", 0)
  engine.ingest_message(
    message([
      records[0],
      {
        name: records[1].name,
        rr_type: 47,
        rr_class: 1,
        cache_flush: true,
        ttl: 2U,
        data: @wire.Nsec(records[1].name, b"\x40"),
        section: @wire.Answer,
      },
    ]),
    "link",
    0,
  )
  assert_false(engine.snapshots()[0].complete)
  assert_true(engine.is_negative("link", records[1].name, 33))
  assert_true(engine.is_negative("link", records[1].name, 16))
  engine.advance(120)
  assert_eq(engine.poll_outbound().unwrap().rr_type, 12)
  assert_true(engine.poll_outbound() is None)
}
