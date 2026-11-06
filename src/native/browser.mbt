///|
pub struct Browser {
  priv engine : @engine.Engine
  scope : String
  interface_ipv4 : UInt32
  interface_index : Int32
  priv socket : MulticastSocket
  priv ingress_policy : IngressPolicy
  priv origin : Int64
  priv mut last_interface_check : Int64
  priv mut closed : Bool
  seed : UInt32
  priv recording : Bool
  priv captures : Array[CaptureFrame]
  priv mut capture_lost : Int64
  priv receive_budget : ReceiveBudget
  priv mut received : Int64
  priv mut accepted : Int64
  priv mut policy_dropped : Int64
  priv mut receive_pauses : Int64
  priv mut packet_rejected : Int64
  priv mut running : Bool
}

///|
pub fn Browser::open(
  interface_ipv4 : UInt32,
  seed~ : UInt32? = None,
  record~ : Bool = false,
  ingress_policy~ : IngressPolicy = IngressPolicy::new(),
  packet_limit~ : Int32 = 256,
  source_limit~ : Int32 = 64,
  source_capacity~ : Int32 = 128,
) -> Browser raise {
  let receive_budget = ReceiveBudget::new(
    packet_limit, source_limit, source_capacity,
  )
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
  // A scope identifies one Browser generation, independently of the scheduling
  // seed and millisecond clock. Never merge scopes from different processes.
  let nonce = @env.rand(16)
  guard nonce is Some(nonce) && nonce.length() == 16 else {
    raise SocketError("scope random nonce unavailable", 0)
  }
  {
    engine: @engine.Engine::new(seed~, packet_limit~),
    socket,
    ingress_policy,
    scope: "ipv4:\{interface_ipv4}:\{index}:\{origin}:\{@model.bytes_hex(nonce)}",
    interface_ipv4,
    interface_index: index,
    origin,
    last_interface_check: 0,
    closed: false,
    seed,
    recording: record,
    captures: [],
    capture_lost: 0,
    receive_budget,
    received: 0,
    accepted: 0,
    policy_dropped: 0,
    receive_pauses: 0,
    packet_rejected: 0,
    running: false,
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
  guard !self.running else { raise DriverBusy }
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
  guard !self.running else { raise DriverBusy }
  let now = self.elapsed()
  let id = self.engine.resolve(instance, self.scope, now, timeout_ms~)
  self.capture_frame(ResolveFrame(now, instance, timeout_ms))
  id
}

///|
pub fn Browser::cancel(self : Browser, id : Int32) -> Unit raise {
  guard !self.closed else { raise BrowserClosed }
  guard !self.running else { raise DriverBusy }
  let now = self.elapsed()
  self.engine.cancel(id, now)
  self.capture_frame(CancelFrame(now, id))
}

///|
fn Browser::classify_io_error(
  self : Browser,
  error : TransportError,
) -> TransportError {
  // An address may disappear between the periodic interface check and I/O.
  if interface_index(self.interface_ipv4) != self.interface_index {
    InterfaceUnavailable
  } else {
    error
  }
}

///|
fn Browser::send_pending(self : Browser) -> Unit raise {
  while self.engine.poll_outbound() is Some(packet) {
    guard packet.scope == self.scope else {
      raise SocketError("outbound scope does not match browser interface", 0)
    }
    self.socket.send(packet.bytes) catch {
      error => raise self.classify_io_error(error)
    }
  }
}

///|
/// Bounded poll. Accept only multicast responses from 5353 on the selected
/// interface. Unicast reception is deliberately excluded from this adapter.
pub fn Browser::poll(
  self : Browser,
  timeout_ms~ : Int32 = 20,
) -> Array[@engine.Event] raise {
  guard !self.running else { raise DriverBusy }
  self.poll_driven(timeout_ms~)
}

///|
fn Browser::poll_driven(
  self : Browser,
  timeout_ms~ : Int32,
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
    if !self.receive_budget.global.available(self.elapsed()) {
      self.receive_pauses += 1
      break
    }
    let received = self.socket.receive(timeout_ms=wait) catch {
      error => raise self.classify_io_error(error)
    }
    match received {
      None => break
      Some(packet) => {
        wait = 0
        self.received += 1
        if !self.receive_budget.allow(packet.source_ipv4, self.elapsed()) {
          continue
        }
        if !self.ingress_policy.accepts(packet, self.interface_index) {
          self.policy_dropped += 1
          continue
        }
        let received_at = self.elapsed()
        self.capture_frame(PacketFrame(received_at, packet))
        self.engine.ingest(
          packet.bytes,
          self.scope,
          received_at,
          source=Some({
            source_ipv4: packet.source_ipv4,
            source_port: packet.source_port,
            interface_index: packet.interface_index,
            destination_ipv4: packet.destination_ipv4,
            ip_ttl: packet.ip_ttl,
          }),
        ) catch {
          @engine.RateLimited => continue
          error => {
            self.packet_rejected += 1
            self.engine.advance(received_at)
            events.push(@engine.Diagnostic("packet_rejected", "\{error}"))
            continue
          }
        }
        self.accepted += 1
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
  guard !self.running else { raise DriverBusy }
  guard !self.closed else { raise BrowserClosed }
  self.running = true
  defer self.finish_run()
  guard duration_ms > 0 && duration_ms <= 86400000 else {
    raise InvalidArgument("duration outside 1..86400000ms")
  }
  let deadline = self.elapsed() + duration_ms.to_int64()
  while !self.closed && self.elapsed() < deadline {
    for event in self.poll_driven(timeout_ms=0) {
      if self.closed {
        break
      }
      on_event(event)
    }
    if self.closed {
      break
    }
    on_tick()
    @async.sleep(10)
  }
}

///|
fn Browser::finish_run(self : Browser) -> Unit {
  self.running = false
  self.close()
}

///|
/// Host notification for a network change even when address/index are unchanged.
/// Stop this generation; reopen and restore subscriptions under a fresh scope.
pub fn Browser::notify_network_changed(self : Browser) -> Unit {
  self.close()
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
