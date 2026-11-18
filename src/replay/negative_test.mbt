///|
test "smoke: NSEC replay preserves negative evidence deterministically and expires" {
  let host = @model.DnsName::parse("peer.local.")
  let packet = @wire.query_with_answers(host, 47, [
    {
      name: host,
      rr_type: 47,
      rr_class: 1,
      cache_flush: true,
      ttl: 2U,
      data: @wire.Nsec(host, b"\x40"),
      section: @wire.Answer,
    },
  ]).to_array()
  packet[2] = b'\x84'
  let hex = @model.bytes_hex(Bytes::makei(packet.length(), i => packet[i]))
  let a = @replay.Replay::new()
  let b = @replay.Replay::new()
  let frame = "{\"kind\":\"packet\",\"at_ms\":0,\"scope\":\"link\",\"packet_hex\":\"\{hex}\"}"
  assert_eq(a.step_line(frame), b.step_line(frame))
  assert_true(a.engine.is_negative("link", host, 28))
  let end = "{\"kind\":\"advance\",\"at_ms\":2000}"
  assert_eq(a.step_line(end), b.step_line(end))
  assert_false(a.engine.is_negative("link", host, 28))
}
