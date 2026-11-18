///|
test "smoke: restricted NSEC bitmap roundtrip and malformed record isolation" {
  let host = @model.DnsName::parse("host.local.")
  for
    bitmap in [
      b"\x40", b"\x00\x00\x00\x08", b"\x40\x00\x00\x08", b"\x00\x00\x80", b"\x00\x00\x00\x00\x40",
    ] {
    let record : @wire.Record = {
      name: host,
      rr_type: 47,
      rr_class: 1,
      cache_flush: true,
      ttl: 120U,
      data: @wire.Nsec(host, bitmap),
      section: @wire.Answer,
    }
    let packet = @wire.query_with_answers(host, 47, [record])
    let decoded = @wire.decode(packet)
    assert_true(
      decoded.records[0].data is @wire.Nsec(_, bits) && bits == bitmap,
    )
  }
  let last = Bytes::makei(32, i => if i == 31 { b'\x01' } else { b'\x00' })
  assert_true(@wire.nsec_contains(last, 255))
  assert_false(@wire.nsec_contains(last, 256))
  // Valid RR envelope, invalid NSEC payload: preserve following valid A.
  let packet : Bytes = b"\x00\x00\x84\x00\x00\x00\x00\x02\x00\x00\x00\x00\x00\x00\x2f\x80\x01\x00\x00\x00\x78\x00\x01\xff\x00\x00\x01\x00\x01\x00\x00\x00\x78\x00\x04\x01\x02\x03\x04"
  let decoded = @wire.decode(packet)
  assert_true(decoded.records[0].data is @wire.Unknown(_))
  assert_true(decoded.records[1].data is @wire.A(_))
}
