///|
async fn link_retry(address : String, restored : String) -> Unit {
  let ip = extended_address(address)
  let monitor = @native.MulticastSocket::open(ip)
  defer monitor.close()
  let browser = @native.Browser::open(ip, seed=Some(31U))
  defer browser.close()
  let name = @model.DnsName::parse("_md-tcproof._tcp.local.")
  let presentation = name.to_presentation()
  let start = @native.monotonic_ms()
  let _ = browser.browse(name)
  let queries : Array[Int64] = []
  let mut restored_at : Int64? = None
  while @native.monotonic_ms() - start < 6500L {
    if restored_at is None && @fs.exists(restored) {
      restored_at = Some(@native.monotonic_ms() - start)
    }
    let _ = browser.poll(timeout_ms=0)
    for _ in 0..<32 {
      guard monitor.receive(timeout_ms=0) is Some(packet) else { break }
      if packet.source_ipv4 != ip ||
        packet.source_port != 5353 ||
        packet.destination_ipv4 != 0xe00000fbU {
        continue
      }
      let dns = @probe.independent_packet(packet.bytes) catch { _ => continue }
      if dns.flags == 0 &&
        dns.questions.any(q => q.name == presentation && q.rr_type == 12) {
        queries.push(@native.monotonic_ms() - start)
      }
    }
    let snapshots = browser.snapshots()
    if !snapshots.is_empty() && restored_at is None {
      fail(
        "Browser discovered an instance before response delivery was restored",
      )
    }
    if snapshots.length() == 2 && snapshots.all(s => s.complete) {
      let instances = snapshots.map(s => s.instance.to_presentation())
      guard instances.contains("zc-known." + presentation) &&
        instances.contains("zc-unknown." + presentation) &&
        restored_at is Some(restored_ms) &&
        queries.length() >= 3 &&
        queries[1] < restored_ms &&
        queries[2] >= restored_ms else {
        fail(
          "missing query retry or unexpected resolved instances: \{Repr(queries)}",
        )
      }
      println(
        Json::object({
          "qm_ms": Json(queries),
          "restore_observed_ms": Json(restored_ms),
          "resolved_ms": Json(@native.monotonic_ms() - start),
          "instances": Json(instances),
        }).stringify(),
      )
      return
    }
    @async.sleep(5)
  }
  fail(
    "Browser did not resolve both instances after response delivery was restored: \{Repr(queries)}",
  )
}
