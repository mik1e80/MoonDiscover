///|
/// One SRV alternative, in connection-attempt order. Addresses belong only to
/// this target; an empty list means address resolution is still pending.
pub struct SrvCandidate {
  priority : Int32
  weight : Int32
  port : Int32
  target : @model.DnsName
  addresses : Array[Bytes]
}

///|
fn clone_candidate(candidate : SrvCandidate) -> SrvCandidate {
  { ..candidate, addresses: candidate.addresses.copy(), }
}

///|
fn srv_key(candidate : SrvCandidate) -> String {
  "\{candidate.priority}:\{candidate.weight}:\{candidate.port}:" +
  @model.bytes_hex(candidate.target.canonical_key())
}

///|
// RFC 2782: ascending priority, randomized zero-weight-first arrangement,
// inclusive [0, sum] tickets, then remove and repeat without replacement.
// This stream is separate from query jitter and stable across TTL refreshes.
fn order_srv(
  candidates : Array[SrvCandidate],
  seed : UInt32,
) -> Array[SrvCandidate] {
  if candidates.length() <= 1 {
    return candidates.copy()
  }
  let pending = candidates.copy()
  pending.sort_by((a, b) => {
    let priority = a.priority.compare(b.priority)
    if priority != 0 {
      priority
    } else {
      srv_key(a).compare(srv_key(b))
    }
  })
  let mut state = seed
  for candidate in pending {
    for c in srv_key(candidate) {
      state = (state ^ c.to_int().reinterpret_as_uint()) * 16777619U
    }
  }
  fn draw(bound : UInt32) -> Int32 {
    // Rejection sampling avoids modulo bias, including weight-sum boundaries.
    let threshold = (0U - bound) % bound
    for ;; {
      state = state * 1664525U + 1013904223U
      if state >= threshold {
        return (state % bound).reinterpret_as_int()
      }
    }
  }
  let result : Array[SrvCandidate] = []
  while !pending.is_empty() {
    let priority = pending[0].priority
    let group : Array[SrvCandidate] = []
    while !pending.is_empty() && pending[0].priority == priority {
      group.push(pending.remove(0))
    }
    for i in 1..<group.length() {
      let j = draw((i + 1).reinterpret_as_uint())
      let saved = group[i]
      group[i] = group[j]
      group[j] = saved
    }
    let pool = group.filter(c => c.weight == 0)
    for candidate in group {
      if candidate.weight > 0 {
        pool.push(candidate)
      }
    }
    let mut sum = 0
    for candidate in pool {
      sum += candidate.weight
    }
    while !pool.is_empty() {
      let ticket = draw((sum + 1).reinterpret_as_uint())
      let mut running = 0
      let mut index = 0
      for i, candidate in pool {
        running += candidate.weight
        if running >= ticket {
          index = i
          break
        }
      }
      let chosen = pool.remove(index)
      sum -= chosen.weight
      result.push(chosen)
    }
  }
  result
}

///|
fn Engine::srv_candidates(
  self : Engine,
  scope : String,
  instance : @model.DnsName,
) -> Array[SrvCandidate] {
  let candidates : Array[SrvCandidate] = []
  // A cache-flush RRSet may span packets. The cache owns the one-second
  // grace/rescue rules; every unexpired SRV remains a live alternative.
  for entry in self.cache.records(scope, instance, 33) {
    if entry.record.data is @wire.Srv(priority, weight, port, target) {
      let addresses : Array[Bytes] = []
      for rr_type in [1, 28] {
        for address in self.cache.records(scope, target, rr_type) {
          match address.record.data {
            @wire.A(bytes) | @wire.Aaaa(bytes) => addresses.push(bytes)
            _ => ()
          }
        }
      }
      addresses.sort()
      candidates.push({ priority, weight, port, target, addresses, })
    }
  }
  let mut seed = self.srv_seed
  for c in scope {
    seed = (seed ^ c.to_int().reinterpret_as_uint()) * 16777619U
  }
  for byte in instance.canonical_key() {
    seed = (seed ^ byte.to_int().reinterpret_as_uint()) * 16777619U
  }
  order_srv(candidates, seed)
}

///|
fn same_candidates(a : Array[SrvCandidate], b : Array[SrvCandidate]) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for i, candidate in a {
    if srv_key(candidate) != srv_key(b[i]) ||
      candidate.addresses != b[i].addresses {
      return false
    }
  }
  true
}
