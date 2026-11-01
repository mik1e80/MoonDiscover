///|
async fn main {
  let args = @env.args()
  guard args.length() == 2 else {
    fail("usage: native_cancel <interface-ipv4>")
  }
  let ip = @socket.Addr::parse(args[1] + ":0").ip()
  let browser = @native.Browser::open(ip)
  let result = @async.with_timeout_opt(25, () => browser.run(5000, _ => ()))
  guard result is None else { fail("expected cancellation") }
  let closed = try {
    let _ = browser.poll()
    false
  } catch {
    _ => true
  }
  guard closed else { fail("cancelled browser was not closed") }
  let reopened = @native.Browser::open(ip)
  let peer = @native.Browser::open(ip)
  reopened.close()
  reopened.close()
  let _ = peer.poll(timeout_ms=0)
  peer.close()
  let invalid = @native.Browser::open(ip)
  let failed = try {
    invalid.run(0, _ => ())
    false
  } catch {
    error => {
      guard error is @native.TransportError::InvalidArgument(_) else {
        fail("wrong run error")
      }
      true
    }
  }
  guard failed else { fail("invalid duration accepted") }
  let invalid_closed = try {
    let _ = invalid.poll()
    false
  } catch {
    @native.BrowserClosed => true
    _ => false
  }
  guard invalid_closed else { fail("failed run leaked its browser") }
  let callback = @native.Browser::open(ip)
  let callback_failed = try {
    callback.run(50, _ => (), on_tick=() => fail("injected callback failure"))
    false
  } catch {
    _ => true
  }
  guard callback_failed else { fail("callback failure lost") }
  guard (try {
    let _ = callback.poll()
    false
  } catch {
    @native.BrowserClosed => true
    _ => false
  }) else {
    fail("callback error leaked browser")
  }
  let code = try {
    let socket = @native.MulticastSocket::open(0U)
    socket.close()
    "unexpected success"
  } catch {
    error => error.diagnostic_code()
  }
  guard code == "invalid_transport_argument" else {
    fail("unstable transport code")
  }
  println(
    "{\"cancelled_run_closed\":true,\"reopened\":true,\"shared_browsers\":true,\"idempotent_close\":true,\"invalid_run_closed\":true,\"callback_error_closed\":true,\"typed_error_code\":true}",
  )
}
