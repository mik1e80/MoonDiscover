///|
test "smoke: public source networks preserve CIDR boundaries" {
  let host = @native.SourceNetwork::new(0xc0000280U, 32)
  assert_true(host.contains(0xc0000280U))
  assert_false(host.contains(0xc0000281U))
  let subnet = @native.SourceNetwork::new(0xc0000280U, 24)
  assert_eq(subnet.network, 0xc0000200U)
  assert_eq(subnet.prefix_length, 24)
  assert_true(subnet.contains(0xc00002ffU))
  assert_false(subnet.contains(0xc0000300U))
  let _ = @native.IngressPolicy::new(
    allowed_sources=[subnet],
    require_ip_ttl_255=true,
  )
}
