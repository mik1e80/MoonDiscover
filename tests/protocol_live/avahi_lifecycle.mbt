///|
async fn avahi_lifecycle_capture(ip : UInt32, marker : String) -> Json {
  let socket = @native.MulticastSocket::open(ip)
  defer socket.close()
  let service = @model.DnsName::parse("_mdavlife._tcp.local.")
  let instance = @model.DnsName::parse("isolated._mdavlife._tcp.local.")
  let host = @model.DnsName::parse("md-avahi-life.local.")
  @fs.write_file(marker, "")
  let records : Map[Int32, @wire.Record] = Map([])
  let wire_samples : Map[Int32, String] = Map([])
  let start = @native.monotonic_ms()
  let mut primed = false
  while @native.monotonic_ms() - start < 15000L {
    guard socket.receive(timeout_ms=20) is Some(packet) &&
      packet.source_ipv4 == ip &&
      packet.source_port == 5353 &&
      packet.destination_ipv4 == 0xe00000fbU else {
      continue
    }
    let message = @wire.decode(packet.bytes) catch { _ => continue }
    guard (message.flags & 0x8000) != 0 else { continue }
    for record in message.records {
      let kind = match record.data {
        @wire.Ptr(target) if record.name.same_name(service) &&
          target.same_name(instance) => if record.ttl == 0U { 0 } else { 12 }
        @wire.Srv(_, _, 18424, target) if record.name.same_name(instance) &&
          target.same_name(host) &&
          record.ttl > 0U => 33
        @wire.Txt(txt) if record.name.same_name(instance) &&
          txt.entries() == [b"stage=avahi"] &&
          record.ttl > 0U => 16
        @wire.A(addr) if record.name.same_name(host) &&
          addr == b"\xc0\x00\x02\x14" &&
          record.ttl > 0U => 1
        _ => continue
      }
      records[kind] = record
      wire_samples[kind] = @model.bytes_hex(packet.bytes)
    }
    if records.get(12) is Some(ptr) &&
      records.get(33) is Some(srv) &&
      records.get(16) is Some(txt) &&
      records.get(1) is Some(address) {
      if !primed {
        @fs.write_file(marker + ".positive", "")
        primed = true
      }
      if records.get(0) is Some(goodbye) {
        return {
          "ptr": @model.bytes_hex(expiry_response([ptr], [])),
          "srv": @model.bytes_hex(expiry_response([srv], [])),
          "components": @model.bytes_hex(
            expiry_response([srv, txt, address], []),
          ),
          "short_components": @model.bytes_hex(
            expiry_response([{ ..srv, ttl: 1U, }, txt, address], []),
          ),
          "goodbye": @model.bytes_hex(expiry_response([goodbye], [])),
          "avahi_srv_ttl_seconds": srv.ttl.to_double(),
          "avahi_goodbye_ttl_seconds": goodbye.ttl.to_double(),
          "avahi_positive_udp": wire_samples[12],
          "avahi_srv_udp": wire_samples[33],
          "avahi_txt_udp": wire_samples[16],
          "avahi_address_udp": wire_samples[1],
          "avahi_goodbye_udp": wire_samples[0],
        }
      }
    }
  }
  fail(
    "Avahi capture lacks required records (observed \{Repr(records.keys().collect())})",
  )
}

///|
priv struct AvahiLifecyclePackets {
  ptr : Bytes
  srv : Bytes
  components : Bytes
  goodbye : Bytes
}

///|
async fn avahi_lifecycle_packets(
  capture : String,
  mode : String,
) -> AvahiLifecyclePackets {
  let input = @fs.read_file(capture).json()
  guard input
    is {
      "ptr": String(ptr),
      "srv": String(srv),
      "components": String(components),
      "short_components": String(short_components),
      "goodbye": String(goodbye),
      ..
    } else {
    fail("incomplete Avahi fixture")
  }
  guard mode == "expiry" || mode == "goodbye" else {
    fail("unknown Avahi lifecycle case")
  }
  {
    ptr: @model.bytes_from_hex(ptr),
    srv: @model.bytes_from_hex(srv),
    components: @model.bytes_from_hex(
      if mode == "expiry" {
        short_components
      } else {
        components
      },
    ),
    goodbye: @model.bytes_from_hex(goodbye),
  }
}

///|
async fn avahi_lifecycle_send(
  ip : UInt32,
  capture : String,
  mode : String,
) -> Json {
  let packets = avahi_lifecycle_packets(capture, mode)
  let socket = @native.MulticastSocket::open(ip)
  defer socket.close()
  let start = @native.monotonic_ms()
  let sent : Array[Json] = []
  fn emit(name : String, packet : Bytes) -> Unit raise {
    socket.send(packet)
    sent.push({
      "packet": name,
      "ms": (@native.monotonic_ms() - start).to_double(),
    })
  }
  emit("ptr", packets.ptr)
  @async.sleep(30)
  emit("components", packets.components)
  if mode == "expiry" {
    @async.sleep(1450)
    emit("fresh_srv", packets.srv)
  } else {
    @async.sleep(290)
    emit("goodbye", packets.goodbye)
    @async.sleep(330)
    emit("late_components", packets.components)
    @async.sleep(1400)
    emit("fresh_ptr", packets.ptr)
  }
  { "sent": Json::array(sent) }
}

///|
fn avahi_lifecycle_receive_packet(
  monitor : @native.MulticastSocket,
  peer : UInt32,
  bytes : Bytes,
) -> Int64 raise {
  let start = @native.monotonic_ms()
  while @native.monotonic_ms() - start < 3200L {
    if monitor.receive(timeout_ms=20) is Some(packet) &&
      packet.source_ipv4 == peer &&
      packet.source_port == 5353 &&
      packet.destination_ipv4 == 0xe00000fbU &&
      packet.interface_index == monitor.interface_index &&
      packet.bytes == bytes {
      return @native.monotonic_ms()
    }
  }
  fail("missing expected Avahi-derived packet in receiver namespace")
}

///|
async fn avahi_lifecycle_receive(
  ip : UInt32,
  peer : UInt32,
  capture : String,
  mode : String,
  marker : String,
) -> Json {
  let packets = avahi_lifecycle_packets(capture, mode)
  let monitor = @native.MulticastSocket::open(ip)
  defer monitor.close()
  let browser = @native.Browser::open(ip, seed=Some(31U))
  defer browser.close()
  let _ = browser.browse(@model.DnsName::parse("_mdavlife._tcp.local."))
  let complete = (_ : Array[@engine.Event]) => {
    browser.snapshots() is [s] &&
    s.complete &&
    s.instance.to_presentation() == "isolated._mdavlife._tcp.local." &&
    s.port == Some(18424) &&
    s.addresses == [b"\xc0\x00\x02\x14"]
  }
  @fs.write_file(marker, "")
  let first = avahi_lifecycle_receive_packet(monitor, peer, packets.components)
  guard wait_lifecycle(browser, 80L, _ => {
    browser.engine_stats().cached_records == 3 && browser.snapshots().is_empty()
  }) else {
    fail("Browser did not cache components ahead of the PTR")
  }
  let ptr = avahi_lifecycle_receive_packet(monitor, peer, packets.ptr)
  let ptr_gap = (ptr - first).to_double()
  if mode == "expiry" {
    guard ptr_gap >= 1050.0 &&
      wait_lifecycle(browser, 250L, _ => {
        browser.snapshots() is [s] &&
        !s.complete &&
        s.port is None &&
        s.txt is Some(_)
      }) else {
      fail("delayed PTR reused expired SRV")
    }
    let fresh = avahi_lifecycle_receive_packet(monitor, peer, packets.srv)
    guard wait_lifecycle(browser, 500L, complete) else {
      fail("fresh Avahi SRV did not restore complete resolution")
    }
    return {
      "arrival": ["components", "ptr", "fresh_srv"],
      "ptr_after_components_ms": ptr_gap,
      "fresh_srv_after_components_ms": (fresh - first).to_double(),
      "observed_partial_then_resolved": true,
    }
  }
  guard ptr_gap > 0.0 && wait_lifecycle(browser, 250L, complete) else {
    fail("Avahi service did not resolve after the delayed PTR")
  }
  let goodbye = avahi_lifecycle_receive_packet(monitor, peer, packets.goodbye)
  let _ = wait_lifecycle(browser, 75L, _ => false)
  guard complete([]) else { fail("goodbye grace missing") }
  let late = avahi_lifecycle_receive_packet(monitor, peer, packets.components)
  guard late > goodbye && late - goodbye < 1000L else {
    fail("components arrived outside goodbye grace")
  }
  guard wait_lifecycle(browser, 1500L, events => {
      events.any(e => e is @engine.Removed(_, "goodbye"))
    }) &&
    browser.snapshots().is_empty() else {
    fail("late Avahi components prevented goodbye removal")
  }
  let removed = @native.monotonic_ms()
  guard removed - goodbye >= 1000L else { fail("goodbye removed before grace") }
  let _ = avahi_lifecycle_receive_packet(monitor, peer, packets.ptr)
  guard wait_lifecycle(browser, 500L, complete) else {
    fail("fresh Avahi PTR did not restore the withdrawn instance")
  }
  {
    "arrival": ["components", "ptr", "goodbye", "late_components", "fresh_ptr"],
    "ptr_after_components_ms": ptr_gap,
    "late_components_after_goodbye_ms": (late - goodbye).to_double(),
    "removed_after_goodbye_ms": (removed - goodbye).to_double(),
    "removed_reason": "goodbye",
    "resolved_again": true,
  }
}
