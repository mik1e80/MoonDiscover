///|
pub struct BrowserBatch {
  events : Array[@engine.Event]
  view : @engine.StateView
}

///|
pub fn Browser::state_view(self : Browser) -> @engine.StateView {
  self.engine.state_view()
}

///|
pub fn Browser::engine_stats(self : Browser) -> @engine.EngineStats {
  self.engine.stats()
}

///|
pub fn Browser::is_negative(
  self : Browser,
  name : @model.DnsName,
  rr_type : Int32,
) -> Bool {
  self.engine.is_negative(self.scope, name, rr_type)
}

///|
/// Prefer whole-view replacement across asynchronous UI/task queues. Compare
/// sequence within the same Browser scope; older queued batches must be ignored.
pub fn Browser::poll_batch(
  self : Browser,
  timeout_ms~ : Int32 = 20,
) -> BrowserBatch raise {
  let events = self.poll(timeout_ms~)
  { events, view: self.state_view(), }
}
