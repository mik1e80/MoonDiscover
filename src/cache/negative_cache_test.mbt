///|
fn nsec_record(
  name : @model.DnsName,
  bitmap : Bytes,
  ttl : UInt32,
) -> @wire.Record {
  {
    name,
    rr_type: 47,
    rr_class: 1,
    cache_flush: true,
    ttl,
    data: @wire.Nsec(name, bitmap),
    section: @wire.Additional,
  }
}

///|
test "smoke: NSEC type scope TTL positive rescue shared PTR and capacity are isolated" {
  let host = @model.DnsName::parse("host.local.")
  let other = @model.DnsName::parse("other.local.")
  let cache = @cache.RecordCache::new(capacity=1)
  let _ = cache.ingest("link", response([nsec_record(host, b"\x40", 2U)]), 0)
  assert_true(cache.is_negative("link", host, 28))
  assert_false(cache.is_negative("link", host, 1))
  assert_false(cache.is_negative("other", host, 28))
  assert_false(cache.is_negative("link", host, 12))
  assert_false(cache.is_negative("link", other, 28))
  assert_true(
    try {
      let _ = cache.ingest(
        "link",
        response([nsec_record(other, b"\x40", 2U)]),
        10,
      )
      false
    } catch {
      @cache.CapacityExceeded => true
      _ => false
    },
  )
  assert_eq(cache.negative_count(), 1)
  let positive : @wire.Record = {
    name: host,
    rr_type: 28,
    rr_class: 1,
    cache_flush: true,
    ttl: 1U,
    data: @wire.Aaaa(Bytes::make(16, 0)),
    section: @wire.Answer,
  }
  let _ = cache.ingest("link", response([positive]), 100)
  assert_false(cache.is_negative("link", host, 28))
  let _ = cache.advance(1100)
  assert_false(cache.is_negative("link", host, 28))
  let _ = cache.advance(2000)
  assert_eq(cache.negative_count(), 0)
}

///|
test "smoke: multiple NSEC names class isolation flush rescue and atomic dual limits" {
  let host = @model.DnsName::parse("one.local.")
  let other = @model.DnsName::parse("two.local.")
  let cache = @cache.RecordCache::new(capacity=2)
  let positive : @wire.Record = {
    name: host,
    rr_type: 1,
    rr_class: 1,
    cache_flush: true,
    ttl: 120U,
    data: @wire.A(b"\x01\x02\x03\x04"),
    section: @wire.Answer,
  }
  let _ = cache.ingest(
    "link",
    response([
      positive,
      nsec_record(host, b"\x00", 120U),
      nsec_record(other, b"\x00\x00\x00\x08", 120U),
    ]),
    0,
  )
  assert_false(cache.is_negative("link", host, 1))
  assert_true(cache.is_negative("link", host, 28))
  assert_false(cache.is_negative("link", other, 28))
  assert_true(cache.is_negative("link", other, 1))
  let _ = cache.ingest(
    "link",
    response([
      { ..positive, data: @wire.A(b"\x04\x03\x02\x01"), },
      nsec_record(host, b"\x00", 120U),
    ]),
    2000,
  )
  assert_eq(cache.records("link", host, 1).length(), 2)
  assert_false(cache.is_negative("link", host, 1))
  let _ = cache.advance(3000)
  assert_eq(cache.records("link", host, 1).length(), 1)
  let _ = cache.ingest(
    "link",
    response([{ ..nsec_record(host, b"\x40", 120U), rr_class: 3, }]),
    3000,
  )
  assert_true(cache.is_negative("link", host, 28))
  let third = @model.DnsName::parse("three.local.")
  assert_true(
    try {
      let _ = cache.ingest(
        "link",
        response([
          { ..positive, name: third, },
          nsec_record(third, b"\x40", 120U),
        ]),
        3001,
      )
      false
    } catch {
      @cache.CapacityExceeded => true
      _ => false
    },
  )
  assert_true(cache.records("link", third, 1).is_empty())
  assert_eq(cache.negative_count(), 2)
}

///|
test "smoke: repeated negative cache update expiry cycles remain bounded" {
  let cache = @cache.RecordCache::new(capacity=64)
  for round in 0..<8 {
    let now = round.to_int64() * 3000L
    let records : Array[@wire.Record] = []
    for i in 0..<64 {
      records.push(
        nsec_record(@model.DnsName::parse("host\{i}.local."), b"\x40", 2U),
      )
    }
    let _ = cache.ingest("link", response(records), now)
    let _ = cache.ingest("link", response(records), now + 1L)
    assert_eq(cache.negative_count(), 64)
    assert_eq(cache.len(), 0)
    let _ = cache.advance(now + 2001L)
    assert_eq(cache.negative_count(), 0)
  }
}

///|
test "smoke: a refreshed NSEC consults earlier live A in its own scope" {
  let cache = @cache.RecordCache::new()
  let host = @model.DnsName::parse("host.local.")
  let positive : @wire.Record = {
    name: host,
    rr_type: 1,
    rr_class: 1,
    cache_flush: true,
    ttl: 1U,
    data: @wire.A(b"\xc0\x00\x02\x01"),
    section: @wire.Answer,
  }
  let _ = cache.ingest("first", response([positive]), 0)
  let nsec = nsec_record(host, b"\x00\x00\x00\x08", 4U)
  let _ = cache.ingest("first", response([nsec]), 100)
  let _ = cache.ingest("second", response([nsec]), 100)
  assert_false(cache.is_negative("first", host, 1))
  assert_true(cache.is_negative("second", host, 1))
  let _ = cache.advance(1000)
  assert_false(cache.is_negative("first", host, 1))
  let _ = cache.ingest("first", response([nsec]), 1100)
  assert_true(cache.is_negative("first", host, 1))
}
