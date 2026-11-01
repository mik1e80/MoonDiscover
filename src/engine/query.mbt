///|
struct QuestionSpec {
  scope : String
  name : @model.DnsName
  rr_type : Int32
}

///|
struct QueryJob {
  question : QuestionSpec
  mut regular_at : Int64?
  mut refresh_at : Int64?
  mut interval_ms : Int64
  mut stamp : String
  mut refresh_step : Int32
}

///|
pub struct Outbound {
  scope : String
  name : @model.DnsName
  rr_type : Int32
  bytes : Bytes
}

///|
fn same_question(a : QuestionSpec, b : QuestionSpec) -> Bool {
  a.scope == b.scope && a.rr_type == b.rr_type && a.name.same_name(b.name)
}

///|
fn Engine::random_below(self : Engine, bound : UInt32) -> Int32 {
  self.rng = self.rng * 1664525U + 1013904223U
  (self.rng % bound).reinterpret_as_int()
}

///|
fn Engine::refresh_deadline(
  self : Engine,
  question : QuestionSpec,
  step : Int32,
) -> Int64? {
  if step >= 4 {
    return None
  }
  let percent = 80L + step.to_int64() * 5L + self.random_below(3U).to_int64()
  let mut result : Int64? = None
  for e in self.cache.records(question.scope, question.name, question.rr_type) {
    // Do not actively refresh records pending goodbye/cache-flush deletion.
    if e.expires_at != e.received_at + e.original_ttl_ms {
      continue
    }
    let time = e.received_at + e.original_ttl_ms * percent / 100L
    if result is None || (result is Some(old) && time < old) {
      result = Some(time)
    }
  }
  result
}

///|
fn Engine::sync_queries(self : Engine) -> Unit {
  let desired : Array[QuestionSpec] = []
  let mut limited = false
  fn want(q : QuestionSpec) {
    if desired.any(other => same_question(q, other)) {
      return
    }
    if desired.length() >= self.query_capacity {
      limited = true
      return
    }
    desired.push(q)
  }
  for sub in self.interests {
    if sub.instance is Some(instance) {
      want({ scope: sub.scope, name: instance, rr_type: 33, })
      want({ scope: sub.scope, name: instance, rr_type: 16, })
    } else {
      want({ scope: sub.scope, name: sub.browse_name, rr_type: 12, })
    }
  }
  for service in self.services {
    want({ scope: service.scope, name: service.instance, rr_type: 33, })
    want({ scope: service.scope, name: service.instance, rr_type: 16, })
    for candidate in service.srv_candidates {
      if candidate.port > 0 && !candidate.target.labels().is_empty() {
        want({ scope: service.scope, name: candidate.target, rr_type: 1, })
        want({ scope: service.scope, name: candidate.target, rr_type: 28, })
      }
    }
  }
  if limited {
    self.emit(Diagnostic("query_limit", "additional questions omitted"))
  }
  let next : Array[QueryJob] = []
  for q in desired {
    let mut existing : QueryJob? = None
    for old in self.jobs {
      if same_question(q, old.question) {
        existing = Some(old)
        break
      }
    }
    let job = match existing {
      Some(value) => value
      None =>
        {
          question: q,
          regular_at: Some(
            self.now_ms + 20L + self.random_below(101U).to_int64(),
          ),
          refresh_at: None,
          interval_ms: 1000,
          stamp: "",
          refresh_step: 0,
        }
    }
    let records = self.cache.records(q.scope, q.name, q.rr_type)
    let stamp = records
      .map(e => "\{e.received_sequence}:\{e.received_at}:\{e.expires_at}")
      .join(",")
    if job.stamp != stamp {
      job.stamp = stamp
      job.refresh_step = 0
      job.refresh_at = self.refresh_deadline(q, 0)
      let unique = records.any(e => e.record.cache_flush)
      if unique {
        job.regular_at = None
      } else if job.regular_at is None {
        job.interval_ms = 1000
        job.regular_at = Some(
          self.now_ms + 20L + self.random_below(101U).to_int64(),
        )
      }
    }
    next.push(job)
  }
  self.jobs = next
  self.pending = self.pending.filter(q => {
    desired.any(other => same_question(q, other))
  })
}

///|
fn Engine::schedule_queries(self : Engine) -> Unit {
  for job in self.jobs {
    let regular_due = job.regular_at is Some(time) && time <= self.now_ms
    let refresh_due = job.refresh_at is Some(time) && time <= self.now_ms
    if !regular_due && !refresh_due {
      continue
    }
    if self.pending.any(q => same_question(q, job.question)) {
      continue
    }
    if self.pending.length() >= 64 {
      self.emit(
        Diagnostic("outbound_limit", "send queue full; queries deferred"),
      )
      if regular_due {
        job.regular_at = Some(self.now_ms + 1000L)
      }
      if refresh_due {
        job.refresh_at = Some(self.now_ms + 1000L)
      }
      continue
    }
    self.pending.push(job.question)
    if regular_due {
      job.regular_at = Some(self.now_ms + job.interval_ms)
      job.interval_ms = (job.interval_ms * 2L).min(3600000L)
    }
    if refresh_due {
      job.refresh_step += 1
      job.refresh_at = self.refresh_deadline(job.question, job.refresh_step)
    }
  }
}

///|
/// Bytes are encoded at polling time, with current remaining TTLs.
/// Drain/send the whole TC continuation burst before changing engine input.
pub fn Engine::poll_outbound(self : Engine) -> Outbound? {
  if !self.fragments.is_empty() {
    return Some(self.fragments.remove(0))
  }
  while !self.pending.is_empty() {
    let q = self.pending.remove(0)
    let answers : Array[@wire.Record] = []
    for e in self.cache.records(q.scope, q.name, q.rr_type) {
      let remaining = e.expires_at - self.now_ms
      if remaining >= (e.original_ttl_ms + 1L) / 2L && remaining >= 1000L {
        answers.push({
          ..e.record,
          ttl: (remaining / 1000L).to_int().reinterpret_as_uint(),
          cache_flush: false,
        })
      }
    }
    let packets = @wire.query_packets(q.name, q.rr_type, answers) catch {
      encoding_error => {
        let plain = @wire.qm_query(q.name, q.rr_type) catch {
          question_error => {
            self.emit(
              Diagnostic(
                "query_invalid",
                "question rejected: \{question_error}",
              ),
            )
            continue
          }
        }
        self.emit(
          Diagnostic(
            "known_answer_limit",
            "known answers omitted; sending plain QM: \{encoding_error}",
          ),
        )
        [plain]
      }
    }
    for bytes in packets {
      self.fragments.push({
        scope: q.scope,
        name: q.name,
        rr_type: q.rr_type,
        bytes,
      })
    }
    return Some(self.fragments.remove(0))
  }
  None
}

///|
fn Engine::discard_burst(self : Engine) -> Unit {
  if !self.fragments.is_empty() {
    self.fragments.clear()
    self.emit(
      Diagnostic(
        "outbound_batch_interrupted", "drain and send every known-answer continuation before changing engine input",
      ),
    )
  }
}
