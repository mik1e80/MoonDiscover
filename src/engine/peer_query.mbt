///|
// Conservative RFC 6762 §7.3 handling. An unauthenticated peer can delay a
// near-due regular question only once between our own emissions. Refresh
// deadlines and TC chains are kept independent.
fn Engine::observe_peer_query(
  self : Engine,
  scope : String,
  message : @wire.Message,
) -> Unit {
  guard message.flags == 0 &&
    message.questions is [question] &&
    message.records.length() <= 255 &&
    question.rr_class == 1 &&
    !question.unicast_response else {
    return
  }
  let requested : QuestionSpec = {
    scope,
    name: question.name,
    rr_type: question.rr_type,
  }
  for job in self.jobs {
    if !same_question(job.question, requested) {
      continue
    }
    let queued = self.pending.any(q => same_question(q, requested))
    guard !job.peer_deferred &&
      (if queued {
        !job.pending_refresh && job.regular_at is Some(_)
      } else {
        job.regular_at is Some(at) && at <= self.now_ms + 120L
      }) else {
      return
    }
    if !message.records.is_empty() {
      let eligible = self.known_answers(requested)
      guard message.records.all(peer => {
        peer.section is @wire.Answer &&
        peer.rr_class == 1 &&
        !peer.cache_flush &&
        peer.ttl > 0U &&
        peer.rr_type == requested.rr_type &&
        peer.name.same_name(requested.name) &&
        eligible.any(known => {
          known.ttl >= peer.ttl && @cache.same_data(known.data, peer.data)
        })
      }) else {
        return
      }
      // When outbound encoding would fall back to a plain QM, the peer's
      // nonempty Known-Answer set is no longer a subset of our planned query.
      let _ = @wire.query_packets(requested.name, requested.rr_type, eligible) catch {
        _ => return
      }
    }
    job.peer_deferred = true
    job.regular_at = Some(self.now_ms + 1000L)
    self.pending = self.pending.filter(q => !same_question(q, requested))
    return
  }
}
