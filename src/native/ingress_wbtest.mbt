///|
fn response() -> Datagram {
  {
    bytes: b"\x00\x00\x84\x00\x00\x00\x00\x00\x00\x00\x00\x00",
    source_ipv4: 0x0a000002U,
    source_port: 5353,
    interface_index: 7,
    destination_ipv4: 0xe00000fbU,
    ip_ttl: Some(255),
  }
}

///|
test "smoke: ingress policy rejects incorrect path and fails closed on strict TTL" {
  let packet = response()
  let policy = IngressPolicy::new()
  assert_true(policy.accepts(packet, 7))
  // A different logical subnet on the same link is allowed by default.
  assert_true(
    policy.accepts({ ..packet, source_ipv4: 0xc0000201U, ip_ttl: Some(64), }, 7),
  )
  for
    rejected in [
      { ..packet, interface_index: 8, },
      { ..packet, destination_ipv4: 0x0a000001U, },
      { ..packet, source_port: 53, },
      { ..packet, bytes: b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00", },
      { ..packet, bytes: b"\x84", },
    ] {
    assert_false(policy.accepts(rejected, 7))
  }
  let networks = [SourceNetwork::new(0x0a0000ffU, 24)]
  let strict = IngressPolicy::new(
    allowed_sources=networks,
    require_ip_ttl_255=true,
  )
  networks.clear()
  assert_true(strict.accepts(packet, 7))
  assert_false(strict.accepts({ ..packet, source_ipv4: 0xc0000201U, }, 7))
  assert_false(strict.accepts({ ..packet, ip_ttl: Some(254), }, 7))
  assert_false(strict.accepts({ ..packet, ip_ttl: None, }, 7))
  assert_true(SourceNetwork::new(0U, 0).contains(0xffffffffU))
  assert_false(SourceNetwork::new(packet.source_ipv4, 32).contains(0x0a000003U))
  assert_true(
    try {
      let _ = SourceNetwork::new(0U, 33)
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      let _ = IngressPolicy::new(
        allowed_sources=Array::make(65, SourceNetwork::new(0U, 0)),
      )
      false
    } catch {
      _ => true
    },
  )
}
