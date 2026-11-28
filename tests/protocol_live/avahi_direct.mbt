///|
fn avahi_direct_records(
  packet : @native.Datagram,
  peer : UInt32,
  interface_index : Int32,
) -> Array[@wire.Record] {
  guard packet.source_ipv4 == peer &&
    packet.source_port == 5353 &&
    packet.interface_index == interface_index &&
    packet.destination_ipv4 == 0xe00000fbU else {
    return []
  }
  let message = @wire.decode(packet.bytes) catch { _ => return [] }
  if (message.flags & 0x8000) != 0 {
    message.records
  } else {
    []
  }
}

///|
fn avahi_direct_ptr(
  records : Array[@wire.Record],
  instance : String,
  goodbye : Bool,
) -> Bool {
  records.any(r => {
    r.name.to_presentation() == "_mdavdirect._tcp.local." &&
    (r.ttl == 0U) == goodbye &&
    r.data is @wire.Ptr(target) &&
    target.to_presentation() == instance
  })
}

///|
async fn avahi_direct_tx(ip : UInt32, mode : String, prefix : String) -> Json {
  let socket = @native.MulticastSocket::open(ip)
  defer socket.close()
  let early = "early._mdavdirect._tcp.local."
  let target = "target._mdavdirect._tcp.local."
  let observed : Map[String, Json] = Map([])
  @fs.write_file(prefix + ".ready", "")
  let deadline = @native.monotonic_ms() + 15000L
  while @native.monotonic_ms() < deadline {
    guard socket.receive(timeout_ms=20) is Some(packet) else { continue }
    let records = avahi_direct_records(packet, ip, socket.interface_index)
    for
      (phase, name, goodbye) in [
        ("early", early, false),
        ("early_goodbye", early, true),
        ("target", target, false),
        ("target_goodbye", target, true),
      ] {
      guard !observed.contains(phase) &&
        avahi_direct_ptr(records, name, goodbye) else {
        continue
      }
      let wire = @model.bytes_hex(packet.bytes)
      let now = @native.monotonic_ms()
      observed[phase] = { "at_ms": now.to_double(), "udp_hex": wire }
      @fs.write_file(prefix + "." + phase, "")
    }
    if observed.contains("early_goodbye") &&
      observed.contains("target") &&
      (mode == "expiry" || observed.contains("target_goodbye")) {
      return { "observed": Json::object(observed) }
    }
  }
  fail("did not capture expected original Avahi packets")
}

///|
fn avahi_direct_complete(browser : @native.Browser, target : String) -> Bool {
  browser
  .snapshots()
  .any(s => {
    s.instance.to_presentation() == target &&
    s.complete &&
    s.port == Some(18424) &&
    s.addresses.contains(b"\xc6\x33\x64\x14")
  })
}

///|
async fn avahi_direct_rx(
  ip : UInt32,
  peer : UInt32,
  mode : String,
  prefix : String,
) -> Json {
  let monitor = @native.MulticastSocket::open(ip)
  defer monitor.close()
  let browser = @native.Browser::open(ip, seed=Some(31U))
  defer browser.close()
  let service = @model.DnsName::parse("_mdavdirect._tcp.local.")
  let _ = browser.browse(service)
  let early = "early._mdavdirect._tcp.local."
  let target = "target._mdavdirect._tcp.local."
  let observed : Map[String, Json] = Map([])
  let mut first_early = -1L
  let mut first_target = -1L
  let mut goodbye_at = -1L
  let mut last_srv = -1L
  let mut srv_packets = 0
  let mut was_complete = false
  @fs.write_file(prefix + ".ready", "")
  let stop = @native.monotonic_ms() +
    (if mode == "expiry" { 145000L } else { 15000L })
  while @native.monotonic_ms() < stop {
    if monitor.receive(timeout_ms=10) is Some(packet) {
      let records = avahi_direct_records(packet, peer, monitor.interface_index)
      let now = @native.monotonic_ms()
      if first_target < 0L && avahi_direct_ptr(records, target, false) {
        first_target = now
        observed["target"] = {
          "at_ms": now.to_double(),
          "udp_hex": @model.bytes_hex(packet.bytes),
        }
      }
      if first_early < 0L && avahi_direct_ptr(records, early, false) {
        first_early = now
        observed["early"] = {
          "at_ms": now.to_double(),
          "udp_hex": @model.bytes_hex(packet.bytes),
        }
      }
      if goodbye_at < 0L && avahi_direct_ptr(records, target, true) {
        goodbye_at = now
        observed["target_goodbye"] = {
          "at_ms": now.to_double(),
          "udp_hex": @model.bytes_hex(packet.bytes),
        }
      }
      for r in records {
        if r.ttl > 0U &&
          r.name.to_presentation() == target &&
          r.data is @wire.Srv(_, _, _, _) {
          guard r.ttl == 120U && r.cache_flush else {
            fail("unexpected original Avahi SRV TTL or cache-flush class")
          }
          last_srv = now
          srv_packets += 1
        }
      }
    }
    let events = browser.poll(timeout_ms=0)
    if !was_complete && avahi_direct_complete(browser, target) {
      was_complete = true
      @fs.write_file(prefix + ".resolved", "")
    }
    if mode == "goodbye" &&
      events.any(e => {
        e is @engine.Removed(s, "goodbye") &&
        s.instance.to_presentation() == target
      }) {
      let elapsed = @native.monotonic_ms() - goodbye_at
      guard was_complete &&
        goodbye_at >= 0L &&
        first_target >= 0L &&
        first_target < goodbye_at &&
        first_early > goodbye_at &&
        first_early - goodbye_at < 1000L &&
        elapsed >= 995L &&
        elapsed <= 1300L &&
        !browser.snapshots().any(s => s.instance.to_presentation() == target) else {
        fail("goodbye sequence or grace failed")
      }
      return {
        "observed": Json::object(observed),
        "late_early_after_goodbye_ms": (first_early - goodbye_at).to_double(),
        "removed_after_goodbye_ms": elapsed.to_double(),
        "removed_reason": "goodbye",
      }
    }
    if mode == "expiry" &&
      was_complete &&
      browser
      .snapshots()
      .any(s => {
        s.instance.to_presentation() == target && s.port is None && !s.complete
      }) {
      let elapsed = @native.monotonic_ms() - last_srv
      guard last_srv >= 0L &&
        first_target >= 0L &&
        first_early > first_target &&
        elapsed >= 119950L &&
        elapsed <= 121000L else {
        fail("SRV did not expire at its original 120-second TTL: \{elapsed} ms")
      }
      return {
        "observed": Json::object(observed),
        "original_srv_ttl_seconds": 120,
        "positive_srv_packets": srv_packets,
        "last_srv_at_ms": last_srv.to_double(),
        "srv_unavailable_after_last_receipt_ms": elapsed.to_double(),
        "ptr_instance_retained": true,
      }
    }
  }
  let snapshots = browser
    .snapshots()
    .map(s => (s.instance.to_presentation(), s.complete, s.port, s.missing))
  fail(
    "direct Avahi \{mode} timed out: resolved=\{was_complete}, early=\{first_early}, target=\{first_target}, goodbye=\{goodbye_at}, positive_srv=\{srv_packets}, snapshots=\{Repr(snapshots)}",
  )
}
