///|
fn ingress_checks(ip : UInt32) -> Json raise {
  let sender = @native.MulticastSocket::open(ip)
  defer sender.close()
  let receiver = @native.MulticastSocket::open(ip)
  defer receiver.close()
  let service = @dnssd.DnsName::parse("_ingress-probe._tcp.local.")
  let instance = @dnssd.DnsName::parse("safe._ingress-probe._tcp.local.")
  let wire = @wire.query_with_answers(service, 12, [
    {
      name: service,
      rr_type: 12,
      rr_class: 1,
      cache_flush: false,
      ttl: 120U,
      data: @dnssd.RData::Ptr(instance),
      section: @dnssd.Section::Answer,
    },
  ]).to_array()
  wire[2] = b'\x84'
  let bytes = Bytes::makei(wire.length(), i => wire[i])
  // A selected physical/virtual interface cannot have this documentation IP in
  // this controlled test; verify before treating it as the denied sender.
  guard ip != 0xc00002ffU else {
    fail("probe exclusion collides with interface")
  }
  let allowed = @native.IngressPolicy::new(
    allowed_sources=[@native.SourceNetwork::new(ip, 32)],
    require_ip_ttl_255=true,
  )
  let denied = @native.IngressPolicy::new(allowed_sources=[
    @native.SourceNetwork::new(0xc00002ffU, 32),
  ])
  let yes = @native.Browser::open(ip, ingress_policy=allowed, record=true)
  defer yes.close()
  let no = @native.Browser::open(ip, ingress_policy=denied, record=true)
  defer no.close()
  let limited = @native.Browser::open(ip, packet_limit=4, source_limit=0)
  defer limited.close()
  let source_limited = @native.Browser::open(
    ip,
    packet_limit=64,
    source_limit=1,
  )
  defer source_limited.close()
  // Overflow capture without changing network settings or needing a long run.
  for _ in 0..<140 {
    let id = yes.browse(@dnssd.DnsName::parse("_unused._tcp.local."))
    yes.cancel(id)
  }
  guard yes.dropped_captures() > 0L else {
    fail("capture fixture did not overflow")
  }
  let _ = yes.browse(service)
  let _ = no.browse(service)
  sender.send(bytes)
  for _ in 0..<16 {
    sender.send(bytes)
  }
  let mut ttl : Int32? = None
  let end = @native.monotonic_ms() + 1500L
  while @native.monotonic_ms() < end {
    if receiver.receive(timeout_ms=10) is Some(packet) && packet.bytes == bytes {
      guard packet.source_ipv4 == ip else { fail("unexpected source IP") }
      ttl = packet.ip_ttl
    }
    let _ = yes.poll(timeout_ms=0)
    let _ = no.poll(timeout_ms=0)
    let _ = limited.poll(timeout_ms=0)
    let _ = source_limited.poll(timeout_ms=0)
    if yes.snapshots().length() == 1 && ttl is Some(_) {
      break
    }
  }
  guard ttl == Some(255) &&
    yes.snapshots().length() == 1 &&
    no.snapshots().is_empty() &&
    yes.scope != no.scope else {
    fail(
      "ingress/TTL/generation checks failed: TTL=\{Repr(ttl)}, accepted=\{yes.snapshots().length()}, denied=\{no.snapshots().length()}",
    )
  }
  let mut accepted_capture = false
  while yes.poll_capture() is Some(frame) {
    if frame is @native.PacketFrame(_, packet) && packet.bytes == bytes {
      accepted_capture = packet.ip_ttl == Some(255) && packet.source_ipv4 == ip
    }
  }
  while no.poll_capture() is Some(frame) {
    guard !(frame is @native.PacketFrame(_, _)) else {
      fail("denied packet recorded")
    }
  }
  guard accepted_capture else { fail("missing accepted packet metadata") }
  guard limited.stats().receive_pauses > 0L &&
    source_limited.stats().source_rate_dropped > 0L else {
    fail("live ingress rate protection was not exercised")
  }
  guard limited.stats().received <= 4L + limited.elapsed() * 4L / 1000L else {
    fail("live token bucket exceeded its bound")
  }
  Json::object({
    "passed": Json(true),
    "received_ip_ttl": Json(255),
    "source_allowlist_accepted": Json(true),
    "source_denied_before_cache_and_capture": Json(true),
    "distinct_browser_scopes": Json(true),
    "capture_overflow_did_not_stop_browse": Json(true),
    "global_rate_receive_pauses": Json(
      limited.stats().receive_pauses.to_double(),
    ),
    "source_rate_dropped": Json(
      source_limited.stats().source_rate_dropped.to_double(),
    ),
  })
}
