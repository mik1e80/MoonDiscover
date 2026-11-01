///|
test "smoke: SRV RRSet spans packets and flush grace expires old alternatives" {
  let records = fixture()
  guard records[1].data is @wire.Srv(_, _, _, host) else { fail("fixture") }
  let preferred : @wire.Record = {
    ..records[1],
    data: @wire.Srv(0, 10, 8081, host),
  }
  let backup : @wire.Record = {
    ..records[1],
    data: @wire.Srv(10, 20, 8082, host),
  }
  let replacement : @wire.Record = {
    ..records[1],
    data: @wire.Srv(20, 0, 9090, host),
  }
  let engine = @engine.Engine::new(seed=73U)
  let _ = engine.browse(records[0].name, "wifi", 0)
  engine.ingest_message(
    message([records[0], preferred, records[2], records[3]]),
    "wifi",
    0,
  )
  engine.ingest_message(message([backup]), "wifi", 500)
  let snapshot = engine.snapshots()[0]
  assert_true(snapshot.complete)
  assert_eq(snapshot.port, Some(8081))
  assert_eq(snapshot.srv_candidates.map(c => c.port), [8081, 8082])
  engine.ingest_message(message([replacement]), "wifi", 2000)
  assert_eq(engine.snapshots()[0].srv_candidates.length(), 3)
  engine.advance(2999)
  assert_eq(engine.snapshots()[0].srv_candidates.length(), 3)
  engine.advance(3000)
  assert_eq(engine.snapshots()[0].srv_candidates.map(c => c.port), [9090])
  assert_eq(engine.snapshots()[0].port, Some(9090))
  assert_true(engine.snapshots()[0].complete)
}

///|
test "smoke: later SRV continuation rescues a flush-marked member without duplicates" {
  let records = fixture()
  guard records[1].data is @wire.Srv(_, _, _, host) else { fail("fixture") }
  let backup : @wire.Record = {
    ..records[1],
    data: @wire.Srv(10, 0, 8082, host),
  }
  let engine = @engine.Engine::new(seed=73U)
  let _ = engine.browse(records[0].name, "wifi", 0)
  engine.ingest_message(message(records), "wifi", 0)
  engine.ingest_message(message([backup]), "wifi", 2000)
  engine.ingest_message(message([records[1]]), "wifi", 2500)
  engine.advance(3000)
  assert_eq(engine.snapshots()[0].srv_candidates.map(c => c.port), [8080, 8082])
  engine.ingest_message(message([backup]), "wifi", 3000)
  assert_eq(engine.snapshots()[0].srv_candidates.length(), 2)
  engine.ingest_message(message([{ ..backup, ttl: 0U, }]), "wifi", 3500)
  engine.advance(4500)
  assert_eq(engine.snapshots()[0].srv_candidates.map(c => c.port), [8080])
  assert_true(engine.snapshots()[0].complete)
}
