///|
test "smoke: malformed public records cannot poison a valid cached set" {
  let cache = @cache.RecordCache::new()
  let name = @model.DnsName::parse("peer.local.")
  let good : @wire.Record = {
    name,
    rr_type: 1,
    rr_class: 1,
    cache_flush: true,
    ttl: 0xffffffffU,
    data: @wire.A(b"\x7f\x00\x00\x01"),
    section: @wire.Answer,
  }
  let _ = cache.ingest(
    "wifi",
    { id: 0, flags: 0x8400, questions: [], records: [good], },
    0,
  )
  for
    data in [
      @wire.A(b"bad"),
      @wire.Aaaa(b"bad"),
      @wire.Srv(-1, 0, 80, name),
      @wire.Srv(0, 65536, 80, name),
      @wire.Srv(0, 0, -1, name),
    ] {
    let invalid : @wire.Record = {
      ..good,
      rr_type: match data {
        @wire.A(_) => 1
        @wire.Aaaa(_) => 28
        _ => 33
      },
      data,
    }
    assert_true(
      try {
        let _ = cache.ingest(
          "wifi",
          {
            id: 0,
            flags: 0x8400,
            questions: [],
            records: [{ ..good, ttl: 0U, }, invalid],
          },
          2000,
        )
        false
      } catch {
        _ => true
      },
    )
    assert_eq(cache.len(), 1)
    assert_eq(cache.records("wifi", name, 1)[0].expires_at, 4294967295000L)
  }
}
