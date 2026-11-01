///|
test "smoke: seeded SRV ordering handles weights zero sets and priority tiers" {
  let host = @model.DnsName::parse("peer.local.")
  let light : SrvCandidate = {
    priority: 0,
    weight: 10,
    port: 8080,
    target: host,
    addresses: [],
  }
  let heavy : SrvCandidate = { ..light, weight: 30, port: 8081, }
  let zero : SrvCandidate = { ..light, weight: 0, port: 8082, }
  let backup : SrvCandidate = {
    ..light,
    priority: 10,
    weight: 65535,
    port: 8083,
  }
  let mut light_count = 0
  let mut heavy_count = 0
  let mut zero_count = 0
  for seed in 0..<1024 {
    let ordered = order_srv(
      [heavy, zero, backup, light],
      seed.reinterpret_as_uint(),
    )
    assert_true(
      same_candidates(
        ordered,
        order_srv([light, backup, zero, heavy], seed.reinterpret_as_uint()),
      ),
    )
    assert_eq(ordered.length(), 4)
    assert_eq(ordered[3].port, 8083)
    assert_true(ordered.any(c => c.port == 8080))
    assert_true(ordered.any(c => c.port == 8081))
    assert_true(ordered.any(c => c.port == 8082))
    match ordered[0].port {
      8080 => light_count += 1
      8081 => heavy_count += 1
      8082 => zero_count += 1
      _ => fail("higher numeric priority selected first")
    }
  }
  // A broad fixed-seed regression, not a statistical performance guarantee.
  assert_true(heavy_count > light_count * 2)
  assert_true(zero_count > 0 && zero_count < light_count)
  let zeros = [zero, { ..zero, port: 8090, }, { ..zero, port: 8091, }]
  let first_ports : Array[Int32] = []
  for seed in 0..<32 {
    let order = order_srv(zeros, seed.reinterpret_as_uint())
    assert_eq(order.length(), 3)
    if !first_ports.contains(order[0].port) {
      first_ports.push(order[0].port)
    }
  }
  assert_eq(first_ports.length(), 3)
  assert_true(order_srv([], 0U).is_empty())
  assert_eq(order_srv([backup], 0U)[0].port, 8083)
  assert_eq(
    order_srv(
      [{ ..light, weight: 65535, }, { ..heavy, weight: 65535, }],
      0xffffffffU,
    ).length(),
    2,
  )
}
