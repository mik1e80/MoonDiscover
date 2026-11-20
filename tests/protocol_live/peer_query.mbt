///|
fn peer_query_checks(ip : UInt32, peer_ip : UInt32) -> Json raise {
  guard ip != peer_ip else { fail("distinct source addresses required") }
  let peer = @native.MulticastSocket::open(peer_ip)
  defer peer.close()
  let browser = @native.Browser::open(ip, seed=Some(31U))
  defer browser.close()
  let name = @model.DnsName::parse("_qm-proof._tcp.local.")
  let _ = browser.browse(name)
  let start = @native.monotonic_ms()
  peer.send(@wire.qm_query(name, 12))
  let mut saw_peer_udp = false
  while @native.monotonic_ms() - start < 2500L {
    let _ = browser.poll(timeout_ms=15)
    if peer.receive(timeout_ms=10) is Some(datagram) {
      let packet = @probe.independent_packet(datagram.bytes) catch {
        _ => continue
      }
      if packet.flags != 0 ||
        !packet.questions.any(q => {
          q.name == name.to_presentation() && q.rr_type == 12
        }) {
        continue
      }
      if datagram.source_ipv4 == peer_ip {
        saw_peer_udp = true
      }
      if datagram.source_ipv4 == ip {
        let elapsed = @native.monotonic_ms() - start
        guard saw_peer_udp && elapsed >= 1000L else {
          fail("Browser sent QM before the peer deferral elapsed")
        }
        return {
          "passed": true,
          "first_local_qm_ms": elapsed,
          "transport": "isolated Linux multicast with two source addresses",
        }
      }
    }
  }
  fail("Browser did not resume sending after peer query")
}
