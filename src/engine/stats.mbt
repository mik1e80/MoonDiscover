///|
/// Logical state counts; these are not byte counts or process RSS.
pub struct EngineStats {
  cached_records : Int32
  services : Int32
  subscriptions : Int32
  queued_events : Int32
  query_jobs : Int32
  queued_questions : Int32
  queued_datagrams : Int32
  dropped_events : Int64
  rate_dropped : Int64
}

///|
pub fn Engine::stats(self : Engine) -> EngineStats {
  {
    cached_records: self.cache.len(),
    services: self.services.length(),
    subscriptions: self.interests.length(),
    queued_events: self.events.length(),
    query_jobs: self.jobs.length(),
    queued_questions: self.pending.length(),
    queued_datagrams: self.fragments.length(),
    dropped_events: self.lost,
    rate_dropped: self.packet_budget.dropped(),
  }
}
