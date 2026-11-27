///|
/// Unauthenticated transport observation supplied by the adapter. Core callers
/// may construct it; it is not proof of origin, ownership or a trusted endpoint.
#derive(Eq)
pub(all) struct PacketSource {
  source_ipv4 : UInt32
  source_port : Int32
  interface_index : Int32
  destination_ipv4 : UInt32
  ip_ttl : Int32?
}

///|
pub extend PacketSource with Eq::{equal, not_equal}
