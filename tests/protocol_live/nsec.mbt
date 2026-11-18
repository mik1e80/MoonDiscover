///|
// Independent Avahi owns this unique IPv4-only name. Its real multicast NSEC,
// not our encoder, must supply the negative AAAA evidence.
fn nsec_checks(ip : UInt32) -> Json raise {
  let socket = @native.MulticastSocket::open(ip)
  defer socket.close()
  let host = @model.DnsName::parse("mdnsec-probe.local.")
  let engine = @dnssd.Engine::new(packet_limit=0)
  defer engine.close()
  let start = @native.monotonic_ms()
  let mut sent_at = -1000L
  let mut found = false
  let mut ttl = 0U
  while @native.monotonic_ms() - start < 5000L {
    let now = @native.monotonic_ms() - start
    if now - sent_at >= 500L {
      socket.send(@wire.qm_query(host, 28))
      sent_at = now
    }
    if socket.receive(timeout_ms=20) is Some(packet) {
      let message = @wire.decode(packet.bytes) catch { _ => continue }
      for record in message.records {
        if record.name.same_name(host) &&
          record.rr_type == 47 &&
          record.data is @wire.Nsec(_, bitmap) &&
          !@wire.nsec_contains(bitmap, 28) {
          engine.ingest(packet.bytes, "avahi", now)
          ttl = record.ttl
          found = engine.is_negative("avahi", host, 28)
        }
      }
      if found {
        break
      }
    }
  }
  guard found && ttl > 0U else { fail("independent Avahi NSEC not received") }
  engine.advance(5000L + ttl.to_int64() * 1000L)
  guard !engine.is_negative("avahi", host, 28) else {
    fail("negative did not expire")
  }
  {
    "passed": true,
    "publisher": "Avahi",
    "transport": "actual IPv4 multicast UDP",
    "aaaa_negative": true,
    "ttl": ttl.to_int64(),
    "virtual_expiry": true,
    "limits": "same Linux VM; expiry advanced in Engine, not physical-time publisher recovery",
  }
}
