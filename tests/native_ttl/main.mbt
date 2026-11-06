///|
extern "C" fn open() -> Int64 = "md_ttl_open"

///|
extern "C" fn port(handle : Int64) -> Int32 = "md_ttl_port"

///|
extern "C" fn route_interface() -> UInt32 = "md_ttl_interface"

///|
extern "C" fn send(port : Int32, ttl : Int32) -> Int32 = "md_ttl_send"

///|
extern "C" fn close(handle : Int64) -> Unit = "moondiscover_socket_close"

///|
#borrow(bytes, metadata)
extern "C" fn receive(
  handle : Int64,
  bytes : FixedArray[Byte],
  size : Int32,
  metadata : FixedArray[Int32],
  timeout : Int32,
) -> Int32 = "moondiscover_socket_receive"

///|
fn main raise {
  let args = @env.args()
  if args.length() == 2 && args[1] == "--interface" {
    let ip = route_interface()
    assert_true(ip != 0U)
    println(
      Json::object({
        "interface_ipv4": Json(
          "\{ip >> 24}.\{(ip >> 16) & 255U}.\{(ip >> 8) & 255U}.\{ip & 255U}",
        ),
      }).stringify(),
    )
    return
  }
  let handle = open()
  assert_true(handle >= 0)
  defer close(handle)
  let port = port(handle)
  assert_true(port > 0)
  for ttl in [255, 254, 1] {
    assert_eq(send(port, ttl), 12)
    let deadline = @native.monotonic_ms() + 1000L
    let mut observed = false
    while @native.monotonic_ms() < deadline {
      let bytes = FixedArray::make(9000, b'\x00')
      let metadata = FixedArray::make(5, -1)
      let count = receive(handle, bytes, 9000, metadata, 50)
      if count == 12 && bytes[11].to_int() == ttl {
        assert_eq(metadata[4], ttl)
        assert_true(metadata[2] > 0)
        assert_eq(metadata[3].reinterpret_as_uint(), 0x7f000001U)
        observed = true
        break
      }
    }
    assert_true(observed)
  }
  println(
    "{\"passed\":true,\"production_receive\":true,\"transport\":\"IPv4 unicast loopback ephemeral port\",\"received_ttls\":[255,254,1],\"mdns_multicast_tested\":false}",
  )
}
