///|
test "smoke: high frequency valid and malformed inputs stop before decode without diagnostic amplification" {
  let engine = @engine.Engine::new(packet_limit=2)
  let records = fixture()
  let _ = engine.browse(records[0].name, "link", 0)
  engine.ingest_message(message(records), "link", 0)
  engine.ingest_message(message(records), "link", 0)
  while engine.poll_event() is Some(_) {
    ()
  }
  for _ in 0..<1000 {
    assert_true(
      try {
        engine.ingest(b"bad", "link", 0)
        false
      } catch {
        @engine.RateLimited => true
        _ => false
      },
    )
  }
  assert_eq(engine.stats().rate_dropped, 1000L)
  assert_true(engine.poll_event() is None)
  assert_true(engine.snapshots()[0].complete)
  engine.ingest_message(message([{ ..records[0], ttl: 0U, }]), "link", 500)
  engine.advance(1500)
  assert_true(engine.snapshots().is_empty())
}
