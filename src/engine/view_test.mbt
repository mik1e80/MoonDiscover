///|
test "smoke: overflow snapshot watermark rejects stale events already copied to an async queue" {
  let engine = @engine.Engine::new(event_capacity=2)
  let records = fixture()
  let id = engine.browse(records[0].name, "link", 0)
  engine.ingest_message(message(records), "link", 0)
  let copied = engine.poll_envelope().unwrap()
  assert_true(copied.event is @engine.Seen(_))
  engine.ingest_message(
    message([
      {
        ..records[2],
        data: @wire.Txt(@model.TxtRecord::from_entries([b"v=2"])),
      },
    ]),
    "link",
    1,
  )
  engine.cancel(id, 2)
  let view = engine.state_view()
  assert_true(view.epoch > copied.epoch)
  assert_true(view.sequence > copied.sequence)
  assert_true(view.snapshots.is_empty())
  while engine.poll_envelope() is Some(envelope) {
    assert_true(
      envelope.epoch == view.epoch && envelope.sequence <= view.sequence,
    )
  }
}
