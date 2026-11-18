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
  if rr_type <= 0 ||
    rr_type > 255 ||
    rr_type == 12 ||
    rr_type == 47 ||
    !self.records(scope, name, rr_type).is_empty() {
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
  now : Int64,
) -> Unit raise CacheError {
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
      }
    }
  }
  // Positive assertions win independent of section or packet order. Remember
  // that contradiction for this NSEC lifetime even after the positive expires.
  self.negatives = self.negatives.map(e => {
    let contradicted = e.contradicted.copy()
    for positive in self.entries {
      if positive.scope == e.scope &&
        positive.record.name.same_name(e.name) &&
        !contradicted.contains(positive.record.rr_type) {
        contradicted.push(positive.record.rr_type)
      }
    }
    { ..e, contradicted, }
  })
}
