///|
/// One bounded name/class/scope NSEC bitmap, logically representing per-type
/// evidence without expanding a packet into hundreds of entries.
struct NegativeEvidence {
  scope : String
  name : @model.DnsName
  bitmap : Bytes
  expires_at : Int64
  contradicted : Array[Int32]
}

///|
pub fn RecordCache::negative_count(self : RecordCache) -> Int32 {
  self.negatives.length()
}

///|
/// DNS-SD shared PTR membership is never suppressed by negative evidence.
pub fn RecordCache::is_negative(
  self : RecordCache,
  scope : String,
  name : @model.DnsName,
  rr_type : Int32,
) -> Bool {
  if rr_type <= 0 || rr_type > 255 || rr_type == 12 || rr_type == 47 {
    return false
  }
  self.negatives.any(e => {
    e.scope == scope &&
    e.name.same_name(name) &&
    e.expires_at > self.now_ms &&
    !e.contradicted.contains(rr_type) &&
    !@wire.nsec_contains(e.bitmap, rr_type)
  })
}

///|
fn RecordCache::accept_negatives(
  self : RecordCache,
  scope : String,
  records : Array[@wire.Record],
  accepted : Array[@wire.Record],
  now : Int64,
) -> Unit raise CacheError {
  let refreshed : Map[Bytes, Unit] = Map([])
  for record in records {
    if record.rr_class != 1 {
      continue
    }
    if record.rr_type == 47 && record.data is @wire.Nsec(_, bitmap) {
      if bitmap.length() < 1 ||
        bitmap.length() > 32 ||
        @wire.nsec_contains(bitmap, 47) {
        continue
      }
      self.negatives = self.negatives.filter(e => {
        !(e.scope == scope && e.name.same_name(record.name))
      })
      if record.ttl != 0 {
        guard self.negatives.length() < self.capacity else {
          raise CapacityExceeded
        }
        self.negatives.push({
          scope,
          name: record.name,
          bitmap,
          expires_at: now + record.ttl.to_int64() * 1000L,
          contradicted: [],
        })
        refreshed[record.name.canonical_key()] = ()
      }
    }
  }
  // Positive assertions win independent of section or packet order. Remember
  // that contradiction for this NSEC lifetime even after the positive expires.
  if self.negatives.is_empty() {
    return
  }
  let assertions : Map[Bytes, Array[Int32]] = Map([])
  fn mark(record : @wire.Record) {
    let key = record.name.canonical_key()
    match assertions.get(key) {
      Some(types) =>
        if !types.contains(record.rr_type) {
          types.push(record.rr_type)
        }
      None => assertions[key] = [record.rr_type]
    }
  }
  for record in accepted {
    if record.ttl != 0 {
      mark(record)
    }
  }
  if !refreshed.is_empty() {
    for entry in self.entries {
      if entry.scope == scope &&
        refreshed.contains(entry.record.name.canonical_key()) {
        mark(entry.record)
      }
    }
  }
  if assertions.is_empty() {
    return
  }
  self.negatives = self.negatives.map(e => {
    if e.scope != scope {
      return e
    }
    guard assertions.get(e.name.canonical_key()) is Some(types) else {
      return e
    }
    let contradicted = e.contradicted.copy()
    for rr_type in types {
      if !contradicted.contains(rr_type) {
        contradicted.push(rr_type)
      }
    }
    { ..e, contradicted, }
  })
}
