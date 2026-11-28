///|
async fn main {
  let args = @env.args()
  guard args.length() >= 3 else {
    fail(
      "usage: protocol_live <packets|subtypes|interface|ingress|nsec-expiry|reordered-lifecycle|peer-query> <ipv4> [marker|peer-ipv4]",
    )
  }
  let address = @socket.Addr::parse(args[2] + ":0")
  guard !address.is_ipv6() else { fail("IPv4 required") }
  let ip = address.ip()
  let report = match args[1] {
    "packets" => packet_checks(ip)
    "ingress" => ingress_checks(ip)
    "nsec-expiry" => nsec_expiry_checks(ip)
    "reordered-lifecycle" => reordered_lifecycle_checks(ip)
    "avahi-direct-tx" => {
      guard args.length() == 5 else {
        fail("direct TX mode and report prefix required")
      }
      avahi_direct_tx(ip, args[3], args[4])
    }
    "avahi-direct-rx" => {
      guard args.length() == 6 else {
        fail("direct RX mode, report prefix and peer required")
      }
      let peer = @socket.Addr::parse(args[5] + ":0")
      guard !peer.is_ipv6() else { fail("IPv4 peer required") }
      avahi_direct_rx(ip, peer.ip(), args[3], args[4])
    }
    "avahi-lifecycle-capture" => {
      guard args.length() == 4 else { fail("capture marker required") }
      avahi_lifecycle_capture(ip, args[3])
    }
    "avahi-lifecycle-send" => {
      guard args.length() == 5 else { fail("capture path and case required") }
      avahi_lifecycle_send(ip, args[3], args[4])
    }
    "avahi-lifecycle-receive" => {
      guard args.length() == 7 else {
        fail("capture path, case, marker and peer required")
      }
      let peer = @socket.Addr::parse(args[6] + ":0")
      guard !peer.is_ipv6() else { fail("IPv4 peer required") }
      avahi_lifecycle_receive(ip, peer.ip(), args[3], args[4], args[5])
    }
    "peer-query" => {
      guard args.length() == 4 else { fail("peer IPv4 required") }
      let peer = @socket.Addr::parse(args[3] + ":0")
      guard !peer.is_ipv6() else { fail("peer IPv4 required") }
      peer_query_checks(ip, peer.ip())
    }
    "subtypes" => subtype_checks(ip)
    "interface" => {
      guard args.length() == 4 else { fail("interface marker required") }
      interface_checks(ip, args[3])
    }
    _ => fail("unknown protocol probe")
  }
  println(report.stringify())
}
