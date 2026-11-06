///|
priv struct SourceBucket {
  ip : UInt32
  budget : @model.PacketBudget
  mut seen : Int64
}

///|
struct ReceiveBudget {
  global : @model.PacketBudget
  source_limit : Int32
  capacity : Int32
  sources : Array[SourceBucket]
  mut source_dropped : Int64
}

///|
fn ReceiveBudget::new(
  packet_limit : Int32,
  source_limit : Int32,
  capacity : Int32,
) -> ReceiveBudget raise {
  guard packet_limit >= 0 &&
    packet_limit <= 65536 &&
    source_limit >= 0 &&
    source_limit <= 65536 &&
    capacity > 0 &&
    capacity <= 256 else {
    raise InvalidArgument("invalid source rate/capacity")
  }
  {
    global: @model.PacketBudget::new(limit=packet_limit),
    source_limit,
    capacity,
    sources: [],
    source_dropped: 0,
  }
}

///|
fn ReceiveBudget::allow(
  self : ReceiveBudget,
  ip : UInt32,
  now : Int64,
) -> Bool raise {
  if !self.global.allow(now) {
    return false
  }
  if self.source_limit == 0 {
    return true
  }
  for source in self.sources {
    if source.ip == ip {
      source.seen = now
      if source.budget.allow(now) {
        return true
      }
      self.source_dropped += 1
      return false
    }
  }
  // Expire idle full buckets; do not evict active senders on every new spoofed IP.
  for i = self.sources.length() - 1; i >= 0; i = i - 1 {
    if now - self.sources[i].seen >= 1000L {
      let _ = self.sources.remove(i)
    }
  }
  if self.sources.length() >= self.capacity {
    self.source_dropped += 1
    return false
  }
  let budget = @model.PacketBudget::new(limit=self.source_limit)
  let _ = budget.allow(now)
  self.sources.push({ ip, budget, seen: now, })
  true
}

///|
pub struct BrowserStats {
  received : Int64
  accepted : Int64
  policy_dropped : Int64
  source_rate_dropped : Int64
  receive_pauses : Int64
  packet_rejected : Int64
  core_rate_dropped : Int64
}

///|
pub fn Browser::stats(self : Browser) -> BrowserStats {
  {
    received: self.received,
    accepted: self.accepted,
    policy_dropped: self.policy_dropped,
    source_rate_dropped: self.receive_budget.source_dropped,
    receive_pauses: self.receive_pauses,
    packet_rejected: self.packet_rejected,
    core_rate_dropped: self.engine.stats().rate_dropped,
  }
}
