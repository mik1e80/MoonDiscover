///|
/// An IPv4 CIDR in host integer order. A /32 permits one source, /0 all sources.
pub struct SourceNetwork {
  network : UInt32
  prefix_length : Int32
  priv mask : UInt32
}

///|
pub fn SourceNetwork::new(
  address : UInt32,
  prefix_length : Int32,
) -> SourceNetwork raise TransportError {
  guard prefix_length >= 0 && prefix_length <= 32 else {
    raise InvalidArgument("source prefix length outside 0..32")
  }
  let mask = if prefix_length == 0 {
    0U
  } else {
    0xffffffffU << (32 - prefix_length)
  }
  { network: address & mask, prefix_length, mask, }
}

///|
pub fn SourceNetwork::contains(self : SourceNetwork, address : UInt32) -> Bool {
  (address & self.mask) == self.network
}

///|
/// Optional application restrictions in addition to multicast/interface checks.
/// Empty allowed_sources preserves RFC 6762 section 11 overlay-subnet behavior.
/// This filters the sender, not advertised endpoints, and does not authenticate it.
pub struct IngressPolicy {
  priv allowed_sources : Array[SourceNetwork]
  priv require_ip_ttl_255 : Bool
}

///|
pub fn IngressPolicy::new(
  allowed_sources~ : Array[SourceNetwork] = [],
  require_ip_ttl_255~ : Bool = false,
) -> IngressPolicy raise TransportError {
  guard allowed_sources.length() <= 64 else {
    raise InvalidArgument("source network limit (64)")
  }
  { allowed_sources: allowed_sources.copy(), require_ip_ttl_255, }
}

///|
/// Called by Browser before capture or ingestion. Rejections are silent and
/// cannot amplify an untrusted stream into diagnostics/events.
pub fn IngressPolicy::accepts(
  self : IngressPolicy,
  packet : Datagram,
  interface_index : Int32,
) -> Bool {
  interface_index > 0 &&
  packet.interface_index == interface_index &&
  packet.destination_ipv4 == 0xe00000fbU &&
  packet.source_port == 5353 &&
  packet.bytes.length() >= 12 &&
  packet.bytes.length() <= 9000 &&
  (packet.bytes[2].to_int() & 0x80) != 0 &&
  (!self.require_ip_ttl_255 || packet.ip_ttl == Some(255)) &&
  (
    self.allowed_sources.is_empty() ||
    self.allowed_sources.any(net => net.contains(packet.source_ipv4))
  )
}
