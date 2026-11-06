///|
pub struct RecordObservation {
  owner : @model.DnsName
  rr_type : Int32
  received_at : Int64
  source : @model.PacketSource
}

///|
fn Engine::observations(
  self : Engine,
  sub : Subscription,
  instance : @model.DnsName,
  candidates : Array[SrvCandidate],
) -> (Array[RecordObservation], Bool) {
  let result : Array[RecordObservation] = []
  let mut truncated = false
  fn add(entries : Array[@cache.CachedRecord]) {
    for entry in entries {
      if entry.source is Some(source) {
        if result.any(old => {
            old.rr_type == entry.record.rr_type &&
            old.owner.same_name(entry.record.name) &&
            old.source == source
          }) {
          continue
        }
        if result.length() == 64 {
          truncated = true
          continue
        }
        result.push({
          owner: entry.record.name,
          rr_type: entry.record.rr_type,
          received_at: entry.received_at,
          source,
        })
      }
    }
  }
  if sub.instance is None {
    add(
      self.cache
      .records(sub.scope, sub.browse_name, 12)
      .filter(e => {
        e.record.data is @wire.Ptr(target) && target.same_name(instance)
      }),
    )
  }
  add(self.cache.records(sub.scope, instance, 33))
  add(newest(self.cache.records(sub.scope, instance, 16)))
  for candidate in candidates {
    add(self.cache.records(sub.scope, candidate.target, 1))
    add(self.cache.records(sub.scope, candidate.target, 28))
  }
  (result, truncated)
}

///|
pub struct EndpointCandidate {
  scope : String
  target : @model.DnsName
  port : Int32
  address : Bytes
  requires_ipv6_zone : Bool
}

///|
/// Explicit application filtering of advertised endpoints, independent of the
/// sender filter. Requires a complete snapshot; preserves SRV candidate order.
/// IPv6 is opt-in and link-local addresses still require adapter zone mapping.
/// A returned candidate is neither reachable nor authenticated by this method.
pub fn ServiceSnapshot::endpoints(
  self : ServiceSnapshot,
  accept : (Bytes, Int32) -> Bool,
  ipv4_only~ : Bool = true,
) -> Array[EndpointCandidate] {
  let result : Array[EndpointCandidate] = []
  if !self.complete {
    return result
  }
  for srv in self.srv_candidates {
    if srv.port == 0 || srv.target.labels().is_empty() {
      continue
    }
    for address in srv.addresses {
      if (address.length() != 4 && (ipv4_only || address.length() != 16)) ||
        !accept(address, srv.port) {
        continue
      }
      result.push({
        scope: self.scope,
        target: srv.target,
        port: srv.port,
        address,
        requires_ipv6_zone: address.length() == 16 &&
        address[0] == b'\xfe' &&
        (address[1].to_int() & 0xc0) == 0x80,
      })
    }
  }
  result
}
