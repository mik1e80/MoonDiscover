///|
async fn interface_checks(ip : UInt32, marker : String) -> Json {
  let browser = @native.Browser::open(ip)
  defer browser.close()
  let _ = browser.browse(@dnssd.DnsName::parse("_http._tcp.local."))
  let old_scope = browser.scope
  let sender = @native.MulticastSocket::open(ip)
  defer sender.close()
  let fixture = @model.bytes_from_hex(
    @fs.read_file("fixtures/zeroconf-0.148.0-response.hex")
    .text()
    .trim()
    .to_owned(),
  )
  sender.send(fixture)
  let seed_deadline = @native.monotonic_ms() + 2000L
  while @native.monotonic_ms() < seed_deadline {
    let _ = browser.poll(timeout_ms=0)
    if browser.snapshots().any(s => s.complete) {
      break
    }
    @async.sleep(10)
  }
  guard browser.snapshots().any(s => s.complete) else {
    fail("isolated interface did not receive seeded service")
  }
  @fs.write_file(marker, "ready")
  let deadline = @native.monotonic_ms() + 5000L
  let mut unavailable = false
  while @native.monotonic_ms() < deadline {
    unavailable = try {
      let _ = browser.poll(timeout_ms=0)
      false
    } catch {
      @native.InterfaceUnavailable => true
      error => raise error
    }
    if unavailable {
      break
    }
    @async.sleep(10)
  }
  guard unavailable else { fail("removed interface address not detected") }
  browser.close()
  guard browser.snapshots().is_empty() else {
    fail("closed old interface retained snapshots")
  }
  guard (try {
    let socket = @native.MulticastSocket::open(ip)
    socket.close()
    false
  } catch {
    @native.InterfaceUnavailable => true
    _ => false
  }) else {
    fail("unavailable address reopened")
  }
  @fs.write_file(marker + ".failed", "detected")
  let recovery_deadline = @native.monotonic_ms() + 5000L
  while @native.interface_index(ip) <= 0 &&
        @native.monotonic_ms() < recovery_deadline {
    @async.sleep(20)
  }
  let recovered = @native.Browser::open(ip)
  defer recovered.close()
  guard recovered.scope != old_scope && recovered.snapshots().is_empty() else {
    fail("network generation/cache isolation")
  }
  let _ = recovered.browse(@dnssd.DnsName::parse("_http._tcp.local."))
  sender.close()
  let new_sender = @native.MulticastSocket::open(ip)
  defer new_sender.close()
  new_sender.send(fixture)
  let resolved_deadline = @native.monotonic_ms() + 2000L
  while @native.monotonic_ms() < resolved_deadline {
    let _ = recovered.poll(timeout_ms=0)
    if recovered.snapshots().any(s => s.complete) {
      break
    }
    @async.sleep(10)
  }
  guard recovered.snapshots().any(s => s.complete) else {
    fail("restored subscription did not resolve service")
  }
  Json::object({
    "passed": Json(true),
    "isolated_network_namespace": Json(true),
    "address_removal_detected": Json(true),
    "old_cache_cleared": Json(true),
    "unavailable_open_rejected": Json(true),
    "new_scope": Json(true),
    "subscription_restored": Json(true),
    "automatic_migration": Json(false),
  })
}
