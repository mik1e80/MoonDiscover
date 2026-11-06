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
/// Prefer whole-view replacement across asynchronous UI/task queues. Compare
/// sequence within the same Browser scope; older queued batches must be ignored.
pub fn Browser::poll_batch(
  self : Browser,
  timeout_ms~ : Int32 = 20,
) -> BrowserBatch raise {
  let events = self.poll(timeout_ms~)
  { events, view: self.state_view(), }
}
