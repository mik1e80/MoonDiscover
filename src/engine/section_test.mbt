///|
test "smoke: response sections support related records but unrelated Additional creates no service" {
  let records = fixture()
  let engine = @engine.Engine::new()
  let _ = engine.browse(records[0].name, "link", 0)
  let unrelated = @model.DnsName::parse("peer._ssh._tcp.local.")
  engine.ingest_message(
    message([
      {
        ..records[0],
        name: @model.DnsName::parse("_ssh._tcp.local."),
        data: @wire.Ptr(unrelated),
        section: @wire.Additional,
      },
      { ..records[1], name: unrelated, section: @wire.Authority, },
    ]),
    "link",
    0,
  )
  assert_true(engine.snapshots().is_empty())
  assert_eq(engine.stats().cached_records, 2)
  // All response RR sections carry assertions; membership comes from matching
  // the PTR owner/target, not from requiring a Question or Answer placement.
  engine.ingest_message(
    message([
      { ..records[0], section: @wire.Additional, },
      { ..records[1], section: @wire.Authority, },
      { ..records[2], section: @wire.Additional, },
      records[3],
    ]),
    "link",
    0,
  )
  assert_eq(engine.snapshots().length(), 1)
  assert_true(engine.snapshots()[0].complete)
}
