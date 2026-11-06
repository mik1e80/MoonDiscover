///|
fn validate_elapsed(
  origin : Int64,
  previous : Int64,
  current : Int64,
) -> Int64 raise TransportError {
  guard current >= origin && current - origin >= previous else {
    raise SocketError("monotonic clock unavailable or regressed", 0)
  }
  current - origin
}

///|
fn Browser::checked_time(self : Browser) -> Int64 raise TransportError {
  let now = validate_elapsed(self.origin, self.clock_at, monotonic_ms())
  self.clock_at = now
  now
}
