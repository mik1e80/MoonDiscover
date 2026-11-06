///|
test "smoke: TXT cross-packet conflict flush grace goodbye and SRV updates follow latest-batch contract" {
  let records = fixture()
  let engine = @engine.Engine::new()
  let _ = engine.browse(records[0].name, "link", 0)
  engine.ingest_message(message(records), "link", 0)
  let a = {
    ..records[2],
    data: @wire.Txt(@model.TxtRecord::from_entries([b"v=a"])),
  }
  let b = {
    ..records[2],
    data: @wire.Txt(@model.TxtRecord::from_entries([b"v=b"])),
  }
  engine.ingest_message(message([a, b]), "link", 2000)
  assert_true(engine.snapshots()[0].missing.contains("ambiguous_txt"))
  engine.ingest_message(message([b]), "link", 2100)
  assert_true(engine.snapshots()[0].complete)
  assert_eq(engine.snapshots()[0].txt.unwrap().lookup("v"), @model.Value(b"b"))
  engine.ingest_message(message([{ ..b, ttl: 0U, }]), "link", 2200)
  engine.ingest_message(
    message([b, { ..records[1], data: @wire.Srv(0, 0, 9090, records[3].name), }]),
    "link",
    3100,
  )
  engine.advance(4100)
  assert_true(engine.snapshots()[0].complete)
  assert_eq(engine.snapshots()[0].port, Some(9090))
  assert_eq(engine.snapshots()[0].txt.unwrap().lookup("v"), @model.Value(b"b"))
}
