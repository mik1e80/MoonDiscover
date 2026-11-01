///|
test "smoke: multiple SRVs resolve by numeric priority and expose alternatives" {
  let records = fixture()
  guard records[1].data is @wire.Srv(_, _, _, host) else { fail("SRV fixture") }
  let preferred : @wire.Record = {
    ..records[1],
    data: @wire.Srv(0, 10, 8081, host),
  }
  let backup : @wire.Record = {
    ..records[1],
    data: @wire.Srv(10, 65535, 8082, host),
  }
  let engine = @engine.Engine::new(seed=73U)
  let _ = engine.browse(records[0].name, "wifi", 0)
  engine.ingest_message(
    message([records[0], backup, preferred, records[2], records[3]]),
    "wifi",
    0,
  )
  assert_true(engine.poll_event() is Some(@engine.Seen(_)))
  assert_true(engine.poll_event() is Some(@engine.Resolved(_)))
  assert_true(engine.snapshots()[0].complete)
  assert_eq(engine.snapshots()[0].port, Some(8081))
  let snapshot = engine.snapshots()[0]
  assert_eq(snapshot.srv_candidates.length(), 2)
  assert_eq(snapshot.srv_candidates[0].priority, 0)
  assert_eq(snapshot.srv_candidates[1].priority, 10)
  assert_eq(snapshot.srv_candidates[1].addresses, [b"\x7f\x00\x00\x01"])
  snapshot.srv_candidates[0].addresses.clear()
  snapshot.srv_candidates.clear()
  assert_eq(engine.snapshots()[0].srv_candidates.length(), 2)
  assert_eq(engine.snapshots()[0].srv_candidates[0].addresses.length(), 1)
  engine.ingest_message(
    message([records[0], preferred, backup, records[2], records[3]]),
    "wifi",
    100,
  )
  assert_eq(engine.snapshots()[0].port, Some(8081))
  assert_true(engine.poll_event() is None)
}

///|
test "smoke: alternative hosts are queried while absent and unavailable SRVs stay partial" {
  let records = fixture()
  let other = @model.DnsName::parse("backup.local.")
  let candidate : @wire.Record = {
    ..records[1],
    data: @wire.Srv(10, 0, 8082, other),
  }
  let engine = @engine.Engine::new(seed=2U)
  let _ = engine.browse(records[0].name, "wifi", 0)
  engine.ingest_message(
    message([records[0], records[1], candidate, records[2], records[3]]),
    "wifi",
    0,
  )
  let _ = engine.poll_event()
  let _ = engine.poll_event()
  engine.advance(120)
  let mut queried = false
  while engine.poll_outbound() is Some(outbound) {
    if outbound.name.same_name(other) && outbound.rr_type == 1 {
      queried = true
    }
  }
  assert_true(queried)
  engine.ingest_message(
    message([
      {
        ..records[1],
        data: @wire.Srv(0, 0, 0, @model.DnsName::from_labels([])),
      },
    ]),
    "wifi",
    200,
  )
  let snapshot = engine.snapshots()[0]
  assert_false(snapshot.complete)
  assert_true(snapshot.target is None && snapshot.port is None)
  assert_true(snapshot.missing.contains("unavailable_srv"))
  assert_true(engine.poll_event() is Some(@engine.Unavailable(_, "response")))
  engine.ingest_message(message([records[1]]), "wifi", 300)
  assert_true(engine.poll_event() is Some(@engine.Resolved(_)))
  assert_true(engine.poll_event() is None)
}
