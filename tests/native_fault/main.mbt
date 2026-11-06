///|
extern "C" fn failure(stage : Int32) -> Unit = "md_probe_failure"

///|
extern "C" fn balance() -> Int32 = "md_probe_balance"

///|
extern "C" fn open(ip : UInt32) -> Int64 = "md_probe_open"

///|
extern "C" fn close(socket : Int64) -> Unit = "md_probe_close"

///|
#borrow(bytes)
extern "C" fn send(socket : Int64, bytes : Bytes, length : Int32) -> Int32 = "md_probe_send"

///|
#borrow(bytes, metadata)
extern "C" fn receive(
  socket : Int64,
  bytes : FixedArray[Byte],
  size : Int32,
  metadata : FixedArray[Int32],
  timeout : Int32,
) -> Int32 = "md_probe_receive"

///|
fn main raise {
  let args = @env.args()
  guard args.length() == 2 else { fail("usage: native_fault <active IPv4>") }
  let ip = @socket.Addr::parse(args[1] + ":0").ip()
  let peer = @native.Browser::open(ip)
  defer peer.close()
  // reuse, pktinfo, bind, membership, multicast interface, multicast TTL.
  for stage in 1..<=6 {
    failure(stage)
    let handle = open(ip)
    if handle >= 0 {
      close(handle)
      fail("injected open failure ignored")
    }
    assert_eq(balance(), 0)
    let _ = peer.poll(timeout_ms=0)
  }
  for stage in [100, 101] {
    failure(stage)
    let handle = open(ip)
    assert_true(handle >= 0)
    let result = if stage == 100 {
      receive(
        handle,
        FixedArray::make(9000, b'\x00'),
        9000,
        FixedArray::make(5, 0),
        0,
      )
    } else {
      send(handle, b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00", 12)
    }
    close(handle)
    assert_true(result < 0)
    assert_eq(balance(), 0)
    let _ = peer.poll(timeout_ms=0)
  }
  failure(0)
  let reopened = open(ip)
  assert_true(reopened >= 0)
  close(reopened)
  assert_eq(balance(), 0)
  println(
    "{\"passed\":true,\"initialization_failures\":6,\"io_failures\":2,\"balanced_handles\":true,\"peer_unaffected\":true,\"reopened\":true}",
  )
}
