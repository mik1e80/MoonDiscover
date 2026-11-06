///|
pub struct EventEnvelope {
  epoch : Int64
  sequence : Int64
  event : Event
}

///|
/// Atomic synchronous snapshot and event watermark for asynchronous consumers.
/// After replacing from this view, discard queued envelopes with sequence <=
/// its watermark or an older epoch. Versions are local to this Engine.
pub struct StateView {
  epoch : Int64
  sequence : Int64
  snapshots : Array[ServiceSnapshot]
}

///|
fn Engine::queue_event(self : Engine, event : Event) -> Unit {
  self.event_sequence += 1
  self.events.push({
    epoch: self.event_epoch,
    sequence: self.event_sequence,
    event,
  })
}

///|
pub fn Engine::poll_envelope(self : Engine) -> EventEnvelope? {
  if self.events.is_empty() {
    None
  } else {
    Some(self.events.remove(0))
  }
}

///|
pub fn Engine::state_view(self : Engine) -> StateView {
  {
    epoch: self.event_epoch,
    sequence: self.event_sequence,
    snapshots: self.snapshots(),
  }
}

///|
fn Engine::rotate_queries(self : Engine) -> Unit {
  if self.query_rotate_at is Some(deadline) && self.now_ms >= deadline {
    self.discard_burst()
    self.query_offset += self.query_capacity
    self.query_rotate_at = Some(self.now_ms + 1000L)
    self.sync_queries()
  }
}
