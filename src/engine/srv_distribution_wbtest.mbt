///|
test "smoke: fixed seed SRV sampling stays in broad RFC ticket probability bands" {
  let host = @model.DnsName::parse("statistics.local.")
  let zero : SrvCandidate = {
    priority: 0,
    weight: 0,
    port: 1,
    target: host,
    addresses: [],
  }
  let counts = [0, 0, 0]
  for seed in 0..<4096 {
    let ordered = order_srv(
      [
        zero,
        { ..zero, weight: 10, port: 2, },
        { ..zero, weight: 30, port: 3, },
        { ..zero, priority: 1, weight: 65535, port: 4, },
      ],
      seed.reinterpret_as_uint(),
    )
    counts[ordered[0].port - 1] += 1
    assert_eq(ordered[3].port, 4)
    let ports = ordered.map(c => c.port)
    ports.sort()
    assert_eq(ports, [1, 2, 3, 4])
  }
  assert_true(counts[0] >= 40 && counts[0] <= 170)
  assert_true(counts[1] >= 780 && counts[1] <= 1250)
  assert_true(counts[2] >= 2700 && counts[2] <= 3250)
}
