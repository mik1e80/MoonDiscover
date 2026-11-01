///|
fn fixture(
  port~ : Int32 = 8080,
  srv_ttl~ : UInt32 = 120,
) -> Array[@wire.Record] raise {
  let service = @model.DnsName::from_utf8_labels(["_http", "_tcp", "local"])
  let instance = @model.DnsName::from_utf8_labels([
    "中文.服务", "_http", "_tcp", "local",
  ])
  let host = @model.DnsName::from_utf8_labels(["host", "local"])
  let txt = @model.TxtRecord::from_entries([b"demo=first", b"raw=\x00\xff"])
  [
    {
      name: service,
      rr_type: 12,
      rr_class: 1,
      cache_flush: false,
      ttl: 120,
      data: @wire.Ptr(instance),
      section: @wire.Answer,
    },
    {
      name: instance,
      rr_type: 33,
      rr_class: 1,
      cache_flush: true,
      ttl: srv_ttl,
      data: @wire.Srv(0, 0, port, host),
      section: @wire.Additional,
    },
    {
      name: instance,
      rr_type: 16,
      rr_class: 1,
      cache_flush: true,
      ttl: 120,
      data: @wire.Txt(txt),
      section: @wire.Additional,
    },
    {
      name: host,
      rr_type: 1,
      rr_class: 1,
      cache_flush: true,
      ttl: 120,
      data: @wire.A(b"\x7f\x00\x00\x01"),
      section: @wire.Additional,
    },
  ]
}

///|
fn message(records : Array[@wire.Record]) -> @wire.Message {
  { id: 0, flags: 0x8400, questions: [], records, }
}

///|
test "smoke: out-of-order records resolve once PTR arrives; repeats are silent" {
  let records = fixture()
  let engine = @engine.Engine::new()
  let _ = engine.browse(records[0].name, "wifi", 0)
  engine.ingest_message(
    message([records[1], records[2], records[3]]),
    "wifi",
    0,
  )
  assert_true(engine.poll_event() is None)
  engine.ingest_message(message([records[0]]), "wifi", 1)
  assert_true(engine.poll_event() is Some(@engine.Seen(_)))
  assert_true(engine.poll_event() is Some(@engine.Resolved(_)))
  assert_true(engine.poll_event() is None)
  let snapshot = engine.snapshots()[0]
  assert_true(snapshot.complete)
  assert_eq(snapshot.port, Some(8080))
  assert_eq(snapshot.instance.labels()[0], records[1].name.labels()[0])
  assert_eq(snapshot.addresses, [b"\x7f\x00\x00\x01"])
  engine.ingest_message(message(records), "wifi", 100)
  assert_true(engine.poll_event() is None)
}

///|
test "smoke: updates expiry and goodbye produce distinct state transitions" {
  let records = fixture(srv_ttl=2)
  let engine = @engine.Engine::new()
  let _ = engine.browse(records[0].name, "wifi", 0)
  engine.ingest_message(message(records), "wifi", 0)
  let _ = engine.poll_event()
  let _ = engine.poll_event()
  let newer = fixture(port=9090, srv_ttl=2)
  engine.ingest_message(message([newer[1]]), "wifi", 1000)
  assert_true(engine.poll_event() is Some(@engine.Updated(_, "response")))
  assert_eq(engine.snapshots()[0].srv_candidates.length(), 2)
  engine.advance(2000)
  assert_eq(engine.snapshots()[0].port, Some(9090))
  assert_true(engine.poll_event() is Some(@engine.Updated(_, "ttl_expired")))
  engine.advance(3000)
  assert_true(
    engine.poll_event() is Some(@engine.Unavailable(_, "ttl_expired")),
  )
  assert_false(engine.snapshots()[0].complete)
  let goodbye : @wire.Record = { ..records[0], ttl: 0, }
  engine.ingest_message(message([goodbye]), "wifi", 4000)
  assert_true(engine.poll_event() is None)
  engine.advance(5000)
  assert_true(engine.poll_event() is Some(@engine.Removed(_, "goodbye")))
  assert_true(engine.snapshots().is_empty())
}

///|
test "smoke: shared subscriptions and same names on different scopes stay isolated" {
  let records = fixture()
  let engine = @engine.Engine::new()
  let a = engine.browse(records[0].name, "wifi", 0)
  let b = engine.browse(records[0].name, "wifi", 0)
  let _ = engine.browse(records[0].name, "ethernet", 0)
  engine.ingest_message(message(records), "wifi", 0)
  engine.ingest_message(message(fixture(port=9090)), "ethernet", 0)
  assert_eq(engine.snapshots().length(), 2)
  for _ in 0..<4 {
    let _ = engine.poll_event()
  }
  engine.cancel(a, 100)
  assert_true(engine.poll_event() is None)
  engine.cancel(b, 100)
  assert_true(engine.poll_event() is Some(@engine.Removed(_, "cancelled")))
  assert_eq(engine.snapshots()[0].scope, "ethernet")
  assert_eq(engine.snapshots()[0].port, Some(9090))
  engine.close()
  engine.close()
  assert_true(engine.snapshots().is_empty())
}

///|
test "smoke: bounded event queue announces lost events and snapshots remain usable" {
  let records = fixture()
  let engine = @engine.Engine::new(event_capacity=2)
  let _ = engine.browse(records[0].name, "a", 0)
  let _ = engine.browse(records[0].name, "b", 0)
  engine.ingest_message(message(records), "a", 0)
  engine.ingest_message(message(records), "b", 0)
  assert_true(engine.dropped_events() > 0L)
  assert_true(
    engine.poll_event() is Some(@engine.Diagnostic("event_overflow", _)),
  )
  assert_eq(engine.snapshots().length(), 2)
  let copy = engine.snapshots()[0]
  copy.addresses.clear()
  assert_eq(engine.snapshots()[0].addresses.length(), 1)
}
