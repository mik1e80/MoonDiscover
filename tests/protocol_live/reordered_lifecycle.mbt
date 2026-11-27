///|
fn multicast_fixture_packet(
  sender : @native.MulticastSocket,
  ip : UInt32,
  bytes : Bytes,
) -> Int64 raise {
  let sent = @native.monotonic_ms()
  sender.send(bytes)
  while @native.monotonic_ms() - sent < 750L {
    if sender.receive(timeout_ms=15) is Some(packet) &&
      packet.bytes == bytes &&
      packet.source_ipv4 == ip &&
      packet.source_port == 5353 &&
      packet.interface_index == sender.interface_index &&
      packet.destination_ipv4 == 0xe00000fbU {
      return sent
    }
  }
  fail("multicast receiver did not observe the sent lifecycle fixture")
}

///|
fn wait_lifecycle(
  browser : @native.Browser,
  timeout_ms : Int64,
  until : (Array[@engine.Event]) -> Bool,
) -> Bool raise {
  let start = @native.monotonic_ms()
  while @native.monotonic_ms() - start < timeout_ms {
    if until(browser.poll(timeout_ms=15)) {
      return true
    }
  }
  false
}

///|
fn reordered_lifecycle_case(ip : UInt32, goodbye : Bool) -> Json raise {
  let sender = @native.MulticastSocket::open(ip)
  defer sender.close()
  let browser = @native.Browser::open(ip, seed=Some(31U))
  defer browser.close()
  let tag = @native.monotonic_ms()
  let service = @model.DnsName::parse(
    "_mdl\{tag.to_int().reinterpret_as_uint()}._tcp.local.",
  )
  let instance = @model.DnsName::parse("split." + service.to_presentation())
  let host = @model.DnsName::parse("split-life\{tag}.local.")
  let _ = browser.browse(service)
  let ptr : @wire.Record = {
    name: service,
    rr_type: 12,
    rr_class: 1,
    ttl: 120U,
    cache_flush: false,
    data: @wire.Ptr(instance),
    section: @wire.Answer,
  }
  let srv = {
    ..ptr,
    name: instance,
    rr_type: 33,
    data: @wire.Srv(0, 0, 18424, host),
  }
  let txt = {
    ..srv,
    rr_type: 16,
    data: @wire.Txt(@model.TxtRecord::from_entries([b"stage=split"])),
  }
  let address = {
    ..srv,
    name: host,
    rr_type: 1,
    data: @wire.A(b"\xc0\x00\x02\x0a"),
  }
  let complete = (_ : Array[@engine.Event]) => {
    browser.snapshots() is [snapshot] &&
    snapshot.instance.same_name(instance) &&
    snapshot.complete &&
    snapshot.port == Some(18424) &&
    snapshot.addresses == [b"\xc0\x00\x02\x0a"]
  }
  let early_srv = if goodbye { srv } else { { ..srv, ttl: 1U, } }
  let components = expiry_response([early_srv, txt, address], [])
  let pointer = expiry_response([ptr], [])
  let first = multicast_fixture_packet(sender, ip, components)
  guard wait_lifecycle(browser, 500L, _ => {
    browser.engine_stats().cached_records >= 3 && browser.snapshots().is_empty()
  }) else {
    fail("early components were not cached before the PTR arrived")
  }
  if !goodbye {
    // Delay the PTR until the already received SRV has expired.
    let _ = wait_lifecycle(browser, 1100L, _ => false)
    let delayed_ptr = multicast_fixture_packet(sender, ip, pointer) - first
    guard wait_lifecycle(browser, 500L, _ => {
      browser.snapshots() is [snapshot] &&
      snapshot.instance.same_name(instance) &&
      !snapshot.complete &&
      snapshot.port is None &&
      snapshot.txt is Some(_)
    }) else {
      fail("delayed PTR did not expose an incomplete instance with expired SRV")
    }
    let _ = multicast_fixture_packet(sender, ip, expiry_response([srv], []))
    guard wait_lifecycle(browser, 500L, complete) else {
      fail("fresh SRV did not resolve the incomplete instance")
    }
    return {
      "case": "srv_expired_before_delayed_ptr",
      "srv_ttl_seconds": 1,
      "ptr_sent_after_components_ms": delayed_ptr.to_double(),
      "partial_without_expired_srv": true,
      "resolved_with_fresh_srv": true,
    }
  }
  let _ = wait_lifecycle(browser, 50L, _ => false)
  let delayed_ptr = multicast_fixture_packet(sender, ip, pointer) - first
  guard wait_lifecycle(browser, 500L, complete) else {
    fail("components followed by PTR did not resolve")
  }
  let withdrawal = expiry_response([{ ..ptr, ttl: 0U, }], [])
  let withdrawn = multicast_fixture_packet(sender, ip, withdrawal)
  let _ = wait_lifecycle(browser, 200L, _ => false)
  guard complete([]) else {
    fail("PTR goodbye removed the service before grace")
  }
  let duplicate_after = multicast_fixture_packet(sender, ip, components) -
    withdrawn
  guard duplicate_after < 1000L else {
    fail("duplicate components missed the goodbye grace window")
  }
  guard wait_lifecycle(browser, 1700L, events => {
    events.any(event => {
      event is @engine.Removed(snapshot, "goodbye") &&
      snapshot.instance.same_name(instance)
    })
  }) else {
    fail("late components prevented PTR goodbye removal")
  }
  let removed_after = @native.monotonic_ms() - withdrawn
  guard removed_after >= 1000L && browser.snapshots().is_empty() else {
    fail("invalid state after PTR goodbye")
  }
  let _ = multicast_fixture_packet(sender, ip, pointer)
  guard wait_lifecycle(browser, 500L, complete) else {
    fail("fresh PTR did not restore discovery after goodbye")
  }
  {
    "case": "late_components_during_ptr_goodbye",
    "ptr_sent_after_components_ms": delayed_ptr.to_double(),
    "duplicate_components_after_goodbye_ms": duplicate_after.to_double(),
    "removed_after_goodbye_ms": removed_after.to_double(),
    "removed_reason": "goodbye",
    "resolved_again_after_fresh_ptr": true,
  }
}

///|
fn reordered_lifecycle_checks(ip : UInt32) -> Json raise {
  let trials : Array[Json] = []
  for _ in 0..<3 {
    trials.push(reordered_lifecycle_case(ip, false))
    trials.push(reordered_lifecycle_case(ip, true))
  }
  {
    "passed": true,
    "trials": trials,
    "transport": "same-host IPv4 multicast, fixture-controlled arrival order",
  }
}
