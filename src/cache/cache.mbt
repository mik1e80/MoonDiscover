///|
pub suberror CacheError {
  InvalidTime
  InvalidScope
  CapacityExceeded
  InvalidRecord(String)
}

///|
pub struct CachedRecord {
  scope : String
  record : @wire.Record
  received_at : Int64
  received_sequence : Int64
  expires_at : Int64
  original_ttl_ms : Int64
}

///|
pub struct Removal {
  scope : String
  record : @wire.Record
  reason : String
}

///|
struct Entry {
  scope : String
  record : @wire.Record
  received_at : Int64
  received_sequence : Int64
  expires_at : Int64
  original_ttl_ms : Int64
  reason : String
}

///|
pub struct RecordCache {
  priv mut entries : Array[Entry]
  priv mut now_ms : Int64
  priv capacity : Int32
  priv mut revision : Int64
}

///|
pub fn RecordCache::new(
  capacity~ : Int32 = 2048,
) -> RecordCache raise CacheError {
  guard capacity > 0 && capacity <= 16384 else { raise CapacityExceeded }
  { entries: [], now_ms: 0, capacity, revision: 0, }
}

///|
fn validate_time(previous : Int64, now : Int64) -> Unit raise CacheError {
  // Leave enough headroom for every UInt32 TTL in milliseconds.
  guard now >= previous && now <= 9223367741887480807L else {
    raise InvalidTime
  }
}

///|
fn same_set(a : @wire.Record, b : @wire.Record) -> Bool {
  a.rr_type == b.rr_type && a.rr_class == b.rr_class && a.name.same_name(b.name)
}

///|
pub fn same_data(a : @wire.RData, b : @wire.RData) -> Bool {
  match (a, b) {
    (@wire.A(x), @wire.A(y)) | (@wire.Aaaa(x), @wire.Aaaa(y)) => x == y
    (@wire.Ptr(x), @wire.Ptr(y)) => x.same_name(y)
    (@wire.Srv(p, w, port, x), @wire.Srv(q, v, other, y)) =>
      p == q && w == v && port == other && x.same_name(y)
    (@wire.Txt(x), @wire.Txt(y)) => x.to_wire() == y.to_wire()
    _ => false
  }
}

///|
fn supported(record : @wire.Record) -> Bool {
  record.rr_class == 1 &&
  (match (record.rr_type, record.data) {
    (1, @wire.A(_))
    | (28, @wire.Aaaa(_))
    | (12, @wire.Ptr(_))
    | (33, @wire.Srv(_, _, _, _))
    | (16, @wire.Txt(_)) => true
    _ => false
  })
}

///|
// ingest_message is a public boundary too: constructed DTOs do not pass through
// the wire decoder. Reject malformed supported IN records atomically.
fn validate_record(record : @wire.Record) -> Unit raise CacheError {
  if record.rr_class != 1 {
    return
  }
  let valid = match (record.rr_type, record.data) {
    (1, @wire.A(bytes)) => bytes.length() == 4
    (28, @wire.Aaaa(bytes)) => bytes.length() == 16
    (33, @wire.Srv(priority, weight, port, _)) =>
      priority >= 0 &&
      priority <= 65535 &&
      weight >= 0 &&
      weight <= 65535 &&
      port >= 0 &&
      port <= 65535
    (12, @wire.Ptr(_)) | (16, @wire.Txt(_)) => true
    (1, _) | (28, _) | (33, _) | (12, _) | (16, _) => false
    _ => true
  }
  guard valid else {
    raise InvalidRecord("invalid IN record type/data or field bounds")
  }
}

///|
pub fn RecordCache::len(self : RecordCache) -> Int32 {
  self.entries.length()
}

///|
pub fn RecordCache::clear(self : RecordCache) -> Unit {
  self.entries = []
}

///|
pub fn RecordCache::advance(
  self : RecordCache,
  now : Int64,
) -> Array[Removal] raise CacheError {
  validate_time(self.now_ms, now)
  let removed : Array[Removal] = []
  let kept : Array[Entry] = []
  for entry in self.entries {
    if entry.expires_at <= now {
      removed.push({
        scope: entry.scope,
        record: entry.record,
        reason: entry.reason,
      })
    } else {
      kept.push(entry)
    }
  }
  self.entries = kept
  self.now_ms = now
  removed
}

///|
/// Atomic packet ingestion. Query Known Answers never become response cache data.
/// Scope is an opaque interface/network-generation identity supplied by the caller.
pub fn RecordCache::ingest(
  self : RecordCache,
  scope : String,
  message : @wire.Message,
  now : Int64,
) -> Array[Removal] raise CacheError {
  validate_time(self.now_ms, now)
  guard scope.length() > 0 && scope.length() <= 256 else { raise InvalidScope }
  let next : RecordCache = {
    entries: self.entries.copy(),
    now_ms: self.now_ms,
    capacity: self.capacity,
    revision: self.revision,
  }
  let removed = next.advance(now)
  // RFC 6762 18.1/18.4/18.5: receive ignores ID, AA and TC (also RD/RA/Z/AD/CD).
  // Structural truncation is still rejected by wire.decode before ingestion.
  if (message.flags & 0xf80f) == 0x8000 {
    guard message.questions.length() <= 256 &&
      message.records.length() <= 256 - message.questions.length() &&
      next.revision < 9223372036854775807L else {
      raise CapacityExceeded
    }
    next.revision += 1
    for record in message.records {
      validate_record(record)
    }
    // PTRs in this DNS-SD cache represent shared membership. Ignore a sender's
    // invalid flush bit both for cache eviction and subsequent query scheduling.
    let records = message.records
      .filter(supported)
      .map(record => {
        if record.rr_type == 12 && record.cache_flush {
          { ..record, cache_flush: false, }
        } else {
          record
        }
      })
    // Apply flush marks to the old set, then rescue every member in this packet.
    // Recently received members survive bursts split across multiple packets.
    next.entries = next.entries.map(entry => {
      let flush = entry.scope == scope &&
        now - entry.received_at > 1000L &&
        records.any(r => {
          r.ttl != 0 && r.cache_flush && same_set(r, entry.record)
        })
      if flush && entry.expires_at > now + 1000L {
        { ..entry, expires_at: now + 1000L, reason: "cache_flush", }
      } else {
        entry
      }
    })
    for record in records {
      let mut index = -1
      for i, entry in next.entries {
        if entry.scope == scope &&
          same_set(entry.record, record) &&
          same_data(entry.record.data, record.data) {
          index = i
          break
        }
      }
      if record.ttl == 0 {
        if index >= 0 {
          let entry = next.entries[index]
          next.entries[index] = {
            ..entry,
            expires_at: now + 1000L,
            reason: "goodbye",
          }
        }
      } else {
        let ttl = record.ttl.to_int64() * 1000L
        let entry : Entry = {
          scope,
          record,
          received_at: now,
          received_sequence: next.revision,
          expires_at: now + ttl,
          original_ttl_ms: ttl,
          reason: "ttl_expired",
        }
        if index >= 0 {
          next.entries[index] = entry
        } else {
          guard next.entries.length() < next.capacity else {
            raise CapacityExceeded
          }
          next.entries.push(entry)
        }
      }
    }
  }
  self.entries = next.entries
  self.now_ms = now
  self.revision = next.revision
  removed
}

///|
pub fn RecordCache::records(
  self : RecordCache,
  scope : String,
  name : @model.DnsName,
  rr_type : Int32,
) -> Array[CachedRecord] {
  self.entries.filter_map(e => {
    if e.scope == scope &&
      e.record.rr_type == rr_type &&
      e.record.name.same_name(name) {
      Some({
        scope: e.scope,
        record: e.record,
        received_at: e.received_at,
        received_sequence: e.received_sequence,
        expires_at: e.expires_at,
        original_ttl_ms: e.original_ttl_ms,
      })
    } else {
      None
    }
  })
}

///|
pub fn RecordCache::next_deadline(self : RecordCache) -> Int64? {
  let mut result : Int64? = None
  for entry in self.entries {
    if result is None || (result is Some(time) && entry.expires_at < time) {
      result = Some(entry.expires_at)
    }
  }
  result
}
