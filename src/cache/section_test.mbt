///|
test "smoke: multicast receive ignores ID and TC while opcode rcode and queries stay excluded" {
  let record = a(b'\x01')
  for flags in [0x8000, 0x8200, 0x87f0] {
    let cache = @cache.RecordCache::new()
    let _ = cache.ingest(
      "link",
      { id: 65535, flags, questions: [], records: [record], },
      0,
    )
    assert_eq(cache.len(), 1)
  }
  for flags in [0, 0x0200, 0x8800, 0x8003] {
    let cache = @cache.RecordCache::new()
    let _ = cache.ingest(
      "link",
      { id: 7, flags, questions: [], records: [record], },
      0,
    )
    assert_eq(cache.len(), 0)
  }
}

///|
test "smoke: section assertions deduplicate and malformed records reject the whole response" {
  let cache = @cache.RecordCache::new()
  let record = a(b'\x01')
  let _ = cache.ingest(
    "link",
    response([
      record,
      { ..record, section: @wire.Authority, },
      { ..record, section: @wire.Additional, },
    ]),
    0,
  )
  assert_eq(cache.len(), 1)
  assert_true(
    try {
      let _ = cache.ingest(
        "link",
        response([
          { ..record, ttl: 0U, },
          { ..record, section: @wire.Additional, data: @wire.A(b"bad"), },
        ]),
        10,
      )
      false
    } catch {
      _ => true
    },
  )
  assert_eq(cache.records("link", record.name, 1)[0].expires_at, 120000L)
}
