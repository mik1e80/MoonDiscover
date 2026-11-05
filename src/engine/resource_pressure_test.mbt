///|
test "smoke: simultaneous cache service query and event limits preserve state and recover" {
  let a = capacity_fixture("_http._tcp.local.", "a", 8001)
  let b = capacity_fixture("_http._tcp.local.", "b", 8002)
  let c = capacity_fixture("_http._tcp.local.", "c", 8003)
  let engine = @engine.Engine::new(
    cache_capacity=7,
    service_capacity=1,
    event_capacity=2,
    query_capacity=1,
  )
  let subscription = engine.browse(a[0].name, "wifi", 0)
  engine.ingest_message(message(a), "wifi", 0)
  engine.ingest_message(message(b), "wifi", 1)
  assert_eq(engine.stats().cached_records, 7)
  assert_eq(engine.stats().query_jobs, 1)
  assert_eq(engine.stats().subscriptions, 1)
  assert_true(engine.dropped_events() > 0)
  assert_eq(engine.snapshots().length(), 1)
  assert_true(engine.snapshots()[0].instance.same_name(a[1].name))
  assert_true(engine.snapshots()[0].complete)
  let before = engine.stats().cached_records
  assert_true(
    try {
      engine.ingest_message(message(c), "wifi", 2)
      false
    } catch {
      _ => true
    },
  )
  assert_eq(engine.stats().cached_records, before)
  assert_true(engine.snapshots()[0].instance.same_name(a[1].name))
  while engine.poll_event() is Some(event) {
    assert_false(event is @engine.Removed(_, _))
  }
  engine.ingest_message(message([{ ..a[0], ttl: 0U, }]), "wifi", 100)
  engine.advance(1100)
  assert_eq(engine.snapshots().length(), 1)
  assert_true(engine.snapshots()[0].instance.same_name(b[1].name))
  assert_true(engine.snapshots()[0].complete)
  engine.cancel(subscription, 1100)
  engine.close()
  let stats = engine.stats()
  assert_eq(
    stats.cached_records +
    stats.services +
    stats.subscriptions +
    stats.query_jobs +
    stats.queued_questions +
    stats.queued_datagrams,
    0,
  )
}
