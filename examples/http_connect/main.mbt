///|
async fn main {
  let args = @env.args()
  guard args.length() == 3 else {
    fail("usage: http_connect <interface-ipv4> <expected-demo-token>")
  }
  let interface = @socket.Addr::parse(args[1] + ":0")
  guard !interface.is_ipv6() else { fail("IPv4 required") }
  let expected = args[2]
  let browser = @native.Browser::open(interface.ip())
  // Controlled same-machine interoperability demo only. The TXT token is a
  // selector, not authentication; never connect to an arbitrary advertised IP.
  defer browser.close()
  let _ = browser.browse(@dnssd.DnsName::parse("_http._tcp.local."))
  let mut chosen : @dnssd.ServiceSnapshot? = None
  while browser.elapsed() < 4000L && chosen is None {
    for event in browser.poll(timeout_ms=0) {
      if event is @dnssd.Event::Resolved(snapshot) && snapshot.txt is Some(txt) {
        if txt.lookup("demo") is @dnssd.TxtValue::Value(bytes) &&
          bytes == @utf8.encode(expected) {
          chosen = Some(snapshot)
        }
      }
    }
    if chosen is None {
      @async.sleep(10)
    }
  }
  guard chosen is Some(service) else {
    fail("expected demo service not resolved")
  }
  let permitted_ip = Bytes::makei(4, i => {
    (interface.ip() >> (24 - i * 8)).to_byte()
  })
  let candidates = service.endpoints((bytes, _) => bytes == permitted_ip)
  guard candidates.get(0) is Some(endpoint) else {
    fail("demo has no IPv4 endpoint")
  }
  let ip = endpoint.address
  let port = endpoint.port
  let host = (ip[0].to_int().reinterpret_as_uint() << 24) |
    (ip[1].to_int().reinterpret_as_uint() << 16) |
    (ip[2].to_int().reinterpret_as_uint() << 8) |
    ip[3].to_int().reinterpret_as_uint()
  let response = @async.with_timeout(3000, () => {
    let connection = @socket.Tcp::connect(@socket.Addr::new(host, port))
    defer connection.close()
    connection.write(
      "GET /moondiscover-demo HTTP/1.1\r\nHost: demo.local\r\nConnection: close\r\n\r\n",
    )
    let bytes : Array[Byte] = []
    while connection.read_some(max_len=4096) is Some(part) {
      guard bytes.length() + part.length() <= 16384 else {
        fail("HTTP demo response exceeds 16 KiB")
      }
      for byte in part {
        bytes.push(byte)
      }
    }
    @utf8.decode(Bytes::makei(bytes.length(), i => bytes[i]))
  })
  guard response.split_once("\r\n\r\n") is Some((headers, body)) else {
    fail("invalid HTTP response")
  }
  guard headers.has_prefix("HTTP/1.0 200") || headers.has_prefix("HTTP/1.1 200") else {
    fail("demo HTTP request failed")
  }
  guard body.trim() == expected else {
    fail("HTTP response does not match the discovered demo token")
  }
  println(
    Json::object({
      "event": Json("http_verified"),
      "instance": Json(service.instance.to_presentation()),
      "discovered_port": Json(port),
      "body": Json(body.trim().to_owned()),
    }).stringify(),
  )
}
