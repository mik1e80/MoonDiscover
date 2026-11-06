///|
test "smoke: source observations follow record chains and endpoint policy filters advertisements independently" {
  let records = fixture()
  let engine = @engine.Engine::new()
  let _ = engine.browse(records[0].name, "link", 0)
  let source : @model.PacketSource = {
    source_ipv4: 0x0a000001U,
    source_port: 5353,
    interface_index: 7,
    destination_ipv4: 0xe00000fbU,
    ip_ttl: Some(255),
  }
  engine.ingest_message(message(records), "link", 0, source=Some(source))
  let snapshot = engine.snapshots()[0]
  assert_eq(snapshot.observations.length(), 4)
  assert_true(
    snapshot.observations.all(o => o.source.source_ipv4 == 0x0a000001U),
  )
  // The sender is permitted, but its advertised loopback endpoint is denied.
  assert_true(snapshot.endpoints((ip, _) => ip[0] == b'\x0a').is_empty())
  assert_eq(snapshot.endpoints((_, port) => port == 8080).length(), 1)
  snapshot.observations.clear()
  assert_eq(engine.snapshots()[0].observations.length(), 4)
}

///|
test "smoke: AAAA only resolution is complete but IPv4 endpoint selection remains empty" {
  let records = fixture()
  let engine = @engine.Engine::new()
  let _ = engine.browse(records[0].name, "link", 0)
  let address = Bytes::makei(16, i => {
    if i == 0 {
      b'\xfe'
    } else if i == 1 {
      b'\x80'
    } else {
      b'\x00'
    }
  })
  engine.ingest_message(
    message([
      records[0],
      records[1],
      records[2],
      { ..records[3], rr_type: 28, data: @wire.Aaaa(address), },
    ]),
    "link",
    0,
  )
  let snapshot = engine.snapshots()[0]
  assert_true(snapshot.complete)
  assert_true(snapshot.endpoints((_, _) => true).is_empty())
  assert_true(
    snapshot.endpoints((_, _) => true, ipv4_only=false)[0].requires_ipv6_zone,
  )
}
