///|
pub struct Browser {
  priv engine : @engine.Engine
  scope : String
  interface_ipv4 : UInt32
  interface_index : Int32
  priv socket : MulticastSocket
  priv origin : Int64
  priv mut last_interface_check : Int64
  priv mut closed : Bool
  seed : UInt32
  priv recording : Bool
  priv captures : Array[CaptureFrame]
  priv mut capture_lost : Int64
}

///|
pub fn Browser::open(
  interface_ipv4 : UInt32,
  seed~ : UInt32? = None,
  record~ : Bool = false,
) -> Browser raise {
  let socket = MulticastSocket::open(interface_ipv4)
  errdefer socket.close()
  let origin = monotonic_ms()
  guard origin >= 0 else { raise SocketError("monotonic clock unavailable", 0) }
  let seed = match seed {
    Some(value) => value
    None => {
      let bytes = @env.rand(4)
      guard bytes is Some(bytes) && bytes.length() == 4 else {
        raise SocketError("random seed unavailable", 0)
      }
      (bytes[0].to_int().reinterpret_as_uint() << 24) |
      (bytes[1].to_int().reinterpret_as_uint() << 16) |
      (bytes[2].to_int().reinterpret_as_uint() << 8) |
      bytes[3].to_int().reinterpret_as_uint()
    }
  }
  let index = socket.interface_index
  {
    engine: @engine.Engine::new(seed~),
    socket,
    scope: "ipv4:\{index}:\{origin}",
    interface_ipv4,
    interface_index: index,
    origin,
    last_interface_check: 0,
    closed: false,
    seed,
    recording: record,
    captures: [],
    capture_lost: 0,
  }
}

///|
pub fn Browser::elapsed(self : Browser) -> Int64 {
  monotonic_ms() - self.origin
}

///|
pub fn Browser::snapshots(self : Browser) -> Array[@engine.ServiceSnapshot] {
  self.engine.snapshots()
}

///|
pub fn Browser::poll_event(self : Browser) -> @engine.Event? {
  self.engine.poll_event()
}

///|
pub fn Browser::browse(
  self : Browser,
  service_type : @model.DnsName,
) -> Int32 raise {
  guard !self.closed else { raise BrowserClosed }
  let now = self.elapsed()
  let id = self.engine.browse(service_type, self.scope, now)
  self.capture_frame(BrowseFrame(now, service_type))
  id
}

///|
pub fn Browser::resolve(
  self : Browser,
  instance : @model.DnsName,
  timeout_ms~ : Int32 = 5000,
) -> Int32 raise {
  guard !self.closed else { raise BrowserClosed }
  let now = self.elapsed()
  let id = self.engine.resolve(instance, self.scope, now, timeout_ms~)
  self.capture_frame(ResolveFrame(now, instance, timeout_ms))
  id
}

///|
pub fn Browser::cancel(self : Browser, id : Int32) -> Unit raise {
  guard !self.closed else { raise BrowserClosed }
  let now = self.elapsed()
  self.engine.cancel(id, now)
  self.capture_frame(CancelFrame(now, id))
}

///|
fn Browser::send_pending(self : Browser) -> Unit raise {
  while self.engine.poll_outbound() is Some(packet) {
    guard packet.scope == self.scope else {
      raise SocketError("outbound scope does not match browser interface", 0)
    }
    self.socket.send(packet.bytes)
  }
}

///|
/// Bounded poll. Accept only multicast responses from 5353 on the selected
/// interface. Unicast reception is deliberately excluded from this adapter.
pub fn Browser::poll(
  self : Browser,
  timeout_ms~ : Int32 = 20,
) -> Array[@engine.Event] raise {
  guard !self.closed else { raise BrowserClosed }
  guard timeout_ms >= 0 && timeout_ms <= 1000 else {
    raise InvalidArgument("poll timeout outside 0..1000ms")
  }
  let now = self.elapsed()
  if now - self.last_interface_check >= 1000L {
    guard interface_index(self.interface_ipv4) == self.interface_index else {
      raise InterfaceUnavailable
    }
    self.last_interface_check = now
  }
  self.engine.advance(now)
  self.capture_frame(AdvanceFrame(now))
  self.send_pending()
  let events : Array[@engine.Event] = []
  let mut wait = timeout_ms.min(50)
  if self.engine.next_deadline() is Some(deadline) {
    wait = wait.min((deadline - now).max(0L).min(50L).to_int())
  }
  for _ in 0..<64 {
    match self.socket.receive(timeout_ms=wait) {
      None => break
      Some(packet) => {
        wait = 0
        if packet.interface_index != self.interface_index ||
          packet.destination_ipv4 != 0xe00000fbU ||
          packet.source_port != 5353 {
          continue
        }
        if packet.bytes.length() >= 12 && (packet.bytes[2].to_int() & 0x80) == 0 {
          continue
        }
        let received_at = self.elapsed()
        self.capture_frame(PacketFrame(received_at, packet))
        self.engine.ingest(packet.bytes, self.scope, received_at) catch {
          error => {
            self.engine.advance(received_at)
            events.push(@engine.Diagnostic("packet_rejected", "\{error}"))
          }
        }
      }
    }
  }
  let after_receive = self.elapsed()
  self.engine.advance(after_receive)
  self.capture_frame(AdvanceFrame(after_receive))
  self.send_pending()
  while self.engine.poll_event() is Some(event) {
    events.push(event)
  }
  events
}

///|
/// Async cooperative polling; cancellation unwinds through close().
pub async fn Browser::run(
  self : Browser,
  duration_ms : Int32,
  on_event : async (@engine.Event) -> Unit,
  on_tick~ : async () -> Unit = () => (),
) -> Unit {
  defer self.close()
  guard duration_ms > 0 && duration_ms <= 86400000 else {
    raise InvalidArgument("duration outside 1..86400000ms")
  }
  let deadline = self.elapsed() + duration_ms.to_int64()
  while self.elapsed() < deadline {
    for event in self.poll(timeout_ms=0) {
      on_event(event)
    }
    on_tick()
    @async.sleep(10)
  }
}

///|
pub fn Browser::close(self : Browser) -> Unit {
  if self.closed {
    return
  }
  let now = self.elapsed()
  self.engine.advance(now) catch {
    _ => ()
  }
  self.capture_frame(CloseFrame(now))
  self.socket.close()
  self.engine.close()
  self.closed = true
}
