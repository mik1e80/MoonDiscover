///|
/// A monotonic token bucket: limit packets/second with a burst of limit.
/// Zero explicitly disables it. No wall clock or background activity.
pub struct PacketBudget {
  priv limit : Int32
  priv mut credit : Int64
  priv mut last : Int64
  priv mut dropped : Int64
}

///|
pub fn PacketBudget::new(limit~ : Int32 = 256) -> PacketBudget raise InputError {
  guard limit >= 0 && limit <= 65536 else {
    raise InvalidInput("packet rate outside 0..65536")
  }
  { limit, credit: limit.to_int64() * 1000L, last: 0, dropped: 0, }
}

///|
fn PacketBudget::refill(
  self : PacketBudget,
  now : Int64,
) -> Unit raise InputError {
  guard now >= self.last && now <= 9223367741887480807L else {
    raise InvalidInput("non-monotonic packet budget time")
  }
  let elapsed = (now - self.last).min(1000L)
  self.credit = (self.credit + elapsed * self.limit.to_int64()).min(
    self.limit.to_int64() * 1000L,
  )
  self.last = now
}

///|
pub fn PacketBudget::available(
  self : PacketBudget,
  now : Int64,
) -> Bool raise InputError {
  self.refill(now)
  self.limit == 0 || self.credit >= 1000L
}

///|
pub fn PacketBudget::allow(
  self : PacketBudget,
  now : Int64,
) -> Bool raise InputError {
  if !self.available(now) {
    if self.dropped < 9223372036854775807L {
      self.dropped += 1
    }
    return false
  }
  if self.limit != 0 {
    self.credit -= 1000L
  }
  true
}

///|
pub fn PacketBudget::dropped(self : PacketBudget) -> Int64 {
  self.dropped
}
