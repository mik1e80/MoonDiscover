///|
pub suberror TransportError {
  SocketError(String, Int64)
  BrowserClosed
  InvalidArgument(String)
  InterfaceUnavailable
}

///|
pub struct MulticastSocket {
  priv mut handle : Int64
  interface_index : Int32
}

///|
pub struct Datagram {
  bytes : Bytes
  source_ipv4 : UInt32
  source_port : Int32
  interface_index : Int32
  destination_ipv4 : UInt32
  ip_ttl : Int32?
}

///|
extern "C" fn socket_open(ip : UInt32) -> Int64 = "moondiscover_socket_open"

///|
pub extern "C" fn interface_index(ip : UInt32) -> Int32 = "moondiscover_interface_index"

///|
pub extern "C" fn monotonic_ms() -> Int64 = "moondiscover_monotonic_ms"

///|
extern "C" fn socket_close(handle : Int64) -> Unit = "moondiscover_socket_close"

///|
#borrow(data)
extern "C" fn socket_send(handle : Int64, data : Bytes, size : Int32) -> Int32 = "moondiscover_socket_send"

///|
#borrow(data, metadata)
extern "C" fn socket_receive(
  handle : Int64,
  data : FixedArray[Byte],
  size : Int32,
  metadata : FixedArray[Int32],
  timeout_ms : Int32,
) -> Int32 = "moondiscover_socket_receive"

///|
/// IPv4 is in host integer order (10.0.0.1 = 0x0a000001).
/// Explicitly close the socket, normally with defer. No automatic background work.
pub fn MulticastSocket::open(
  interface_ipv4 : UInt32,
) -> MulticastSocket raise TransportError {
  guard interface_ipv4 != 0 else {
    raise InvalidArgument("explicit IPv4 interface required")
  }
  let index = interface_index(interface_ipv4)
  guard index > 0 else { raise InterfaceUnavailable }
  let handle = socket_open(interface_ipv4)
  guard handle >= 0 else { raise SocketError("open/bind/join", -handle) }
  { handle, interface_index: index, }
}

///|
pub fn MulticastSocket::close(self : MulticastSocket) -> Unit {
  if self.handle >= 0 {
    socket_close(self.handle)
    self.handle = -1
  }
}

///|
pub fn MulticastSocket::send(
  self : MulticastSocket,
  data : Bytes,
) -> Unit raise TransportError {
  guard self.handle >= 0 else { raise BrowserClosed }
  guard data.length() >= 12 && data.length() <= 9000 else {
    raise InvalidArgument("datagram length outside 12..9000")
  }
  let n = socket_send(self.handle, data, data.length())
  guard n == data.length() else {
    raise SocketError("send", if n < 0 { -n.to_int64() } else { n.to_int64() })
  }
}

///|
/// Bounded synchronous poll for M0. Not an async event-loop integration.
/// Receive metadata is required. Timeout or a discarded truncated datagram
/// returns None; genuine socket failures raise.
pub fn MulticastSocket::receive(
  self : MulticastSocket,
  timeout_ms~ : Int32 = 50,
) -> Datagram? raise TransportError {
  guard self.handle >= 0 else { raise BrowserClosed }
  guard timeout_ms >= 0 && timeout_ms <= 1000 else {
    raise InvalidArgument("timeout outside 0..1000ms")
  }
  let data = FixedArray::make(9000, b'\x00')
  let metadata = FixedArray::make(5, 0)
  metadata[4] = -1
  let n = socket_receive(self.handle, data, 9000, metadata, timeout_ms)
  if n == 0 || n > data.length() {
    return None
  }
  guard n > 0 else { raise SocketError("receive", -n.to_int64()) }
  guard metadata[2] > 0 else {
    raise SocketError("missing ingress interface metadata", 0)
  }
  Some({
    bytes: Bytes::makei(n, i => data[i]),
    source_ipv4: metadata[0].reinterpret_as_uint(),
    source_port: metadata[1],
    interface_index: metadata[2],
    destination_ipv4: metadata[3].reinterpret_as_uint(),
    ip_ttl: if metadata[4] >= 0 && metadata[4] <= 255 {
      Some(metadata[4])
    } else {
      None
    },
  })
}
