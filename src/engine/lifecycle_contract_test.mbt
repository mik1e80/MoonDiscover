///|
test "smoke: host port and address changes follow the published event contract" {
  let records = fixture()
  let engine = @engine.Engine::new()
  let _ = engine.browse(records[0].name, "wifi", 0)
  engine.ingest_message(message(records), "wifi", 0)
  let _ = engine.poll_event()
  let _ = engine.poll_event()
  engine.ingest_message(message([fixture(port=9090)[1]]), "wifi", 2000)
  engine.advance(3000)
  assert_eq(engine.snapshots()[0].port, Some(9090))
  let mut updated = false
  while engine.poll_event() is Some(event) {
    if event is @engine.Updated(_, _) {
      updated = true
    }
  }
  assert_true(updated)
  let host = @model.DnsName::parse("replacement.local.")
  engine.ingest_message(
    message([{ ..records[1], data: @wire.Srv(0, 0, 9090, host), }]),
    "wifi",
    5000,
  )
  engine.advance(6000)
  assert_true(engine.snapshots()[0].missing.contains("addresses"))
  let mut unavailable = false
  while engine.poll_event() is Some(event) {
    if event is @engine.Unavailable(_, _) {
      unavailable = true
    }
  }
  assert_true(unavailable)
  engine.ingest_message(
    message([{ ..records[3], name: host, ttl: 1U, }]),
    "wifi",
    6100,
  )
  assert_true(
    engine.poll_event() is Some(@engine.Resolved(s)) &&
    s.target is Some(t) &&
    t.same_name(host),
  )
  engine.advance(7100)
  assert_true(
    engine.poll_event() is Some(@engine.Unavailable(_, "ttl_expired")),
  )
  engine.ingest_message(message([{ ..records[3], name: host, }]), "wifi", 7200)
  assert_true(engine.poll_event() is Some(@engine.Resolved(_)))
  assert_true(engine.poll_event() is None)
  assert_eq(engine.stats().services, 1)
}

///|
test "smoke: removing one service preserves a peer sharing the same host" {
  let records = fixture()
  let peer = @model.DnsName::parse("peer._http._tcp.local.")
  let engine = @engine.Engine::new()
  let subscription = engine.browse(records[0].name, "wifi", 0)
  engine.ingest_message(
    message([
      records[0],
      records[1],
      records[2],
      records[3],
      { ..records[0], data: @wire.Ptr(peer), },
      { ..records[1], name: peer, },
      { ..records[2], name: peer, },
    ]),
    "wifi",
    0,
  )
  while engine.poll_event() is Some(_) {
    ()
  }
  engine.ingest_message(message([{ ..records[0], ttl: 0U, }]), "wifi", 100)
  engine.advance(1100)
  assert_true(
    engine.poll_event() is Some(@engine.Removed(s, "goodbye")) &&
    s.instance.same_name(records[1].name),
  )
  assert_true(engine.poll_event() is None)
  assert_eq(engine.snapshots().length(), 1)
  assert_true(engine.snapshots()[0].instance.same_name(peer))
  assert_true(engine.snapshots()[0].complete)
  assert_eq(engine.snapshots()[0].addresses, [b"\x7f\x00\x00\x01"])
  assert_eq(engine.stats().services, 1)
  engine.cancel(subscription, 1100)
  assert_eq(engine.stats().subscriptions, 0)
  assert_eq(engine.stats().query_jobs, 0)
  assert_eq(engine.stats().queued_questions, 0)
  assert_eq(engine.stats().queued_datagrams, 0)
}
