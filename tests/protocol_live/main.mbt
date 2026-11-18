///|
async fn main {
  let args = @env.args()
  guard args.length() >= 3 else {
    fail(
      "usage: protocol_live <packets|subtypes|interface|ingress> <ipv4> [marker]",
    )
  }
  let address = @socket.Addr::parse(args[2] + ":0")
  guard !address.is_ipv6() else { fail("IPv4 required") }
  let ip = address.ip()
  let report = match args[1] {
    "packets" => packet_checks(ip)
    "ingress" => ingress_checks(ip)
    "subtypes" => subtype_checks(ip)
    "interface" => {
      guard args.length() == 4 else { fail("interface marker required") }
      interface_checks(ip, args[3])
    }
    _ => fail("unknown protocol probe")
  }
  println(report.stringify())
}
