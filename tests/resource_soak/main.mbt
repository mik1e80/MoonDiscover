///|
extern "C" fn rss() -> Int64 = "moondiscover_probe_rss"

///|
extern "C" fn handles() -> Int64 = "moondiscover_probe_handles"

///|
fn workload() -> @dnssd.Message raise {
  let service = @dnssd.DnsName::parse("_soak._tcp.local.")
  let host = @dnssd.DnsName::parse("soak-host.local.")
  let records : Array[@dnssd.Record] = []
  for i in 0..<50 {
    let instance = @dnssd.DnsName::parse("service-\{i}._soak._tcp.local.")
    for
      (name, rr_type, data, cache_flush) in [
        (service, 12, @dnssd.RData::Ptr(instance), false),
        (instance, 33, @dnssd.RData::Srv(0, 0, 18080, host), true),
        (
          instance,
          16,
          @dnssd.RData::Txt(@dnssd.TxtRecord::from_entries([b"phase=one"])),
          true,
        ),
      ] {
      records.push({
        name,
        rr_type,
        data,
        cache_flush,
        rr_class: 1,
        ttl: 2U,
        section: @dnssd.Section::Answer,
      })
    }
  }
  records.push({
    name: host,
    rr_type: 1,
    rr_class: 1,
    cache_flush: true,
    ttl: 2U,
    data: @dnssd.RData::A(b"\x7f\x00\x00\x01"),
    section: @dnssd.Section::Answer,
  })
  { id: 0, flags: 0x8400, questions: [], records, }
}

///|
fn cycle(input : @dnssd.Message) -> Int64 raise {
  let engine = @dnssd.Engine::new(
    cache_capacity=256,
    service_capacity=60,
    event_capacity=8,
    query_capacity=200,
    seed=7U,
  )
  defer engine.close()
  let _ = engine.browse(input.records[0].name, "soak", 0)
  engine.ingest_message(input, "soak", 0)
  for _ in 0..<5 {
    engine.ingest_message(input, "soak", 0)
  }
  guard engine.stats().cached_records == 151 &&
    engine.snapshots().length() == 50 &&
    engine.snapshots().all(s => s.complete) else {
    fail("duplicate/cache/snapshot invariant")
  }
  let mut overflow = false
  while engine.poll_event() is Some(event) {
    if event is @dnssd.Event::Diagnostic("event_overflow", _) {
      overflow = true
    }
  }
  guard overflow && engine.dropped_events() > 0 else {
    fail("queue pressure did not exercise snapshot resynchronization")
  }
  let updated : @dnssd.Message = {
    ..input,
    records: input.records
    .filter(r => r.rr_type == 16)
    .map(r => {
      ..r,
      data: @dnssd.RData::Txt(@dnssd.TxtRecord::from_entries([b"phase=two"])),
    }),
  }
  engine.ingest_message(updated, "soak", 100)
  guard engine.stats().cached_records == 201 else {
    fail("update cache count invariant")
  }
  guard engine
    .snapshots()
    .all(s => {
      s.txt is Some(txt) &&
      txt.lookup("phase") == @dnssd.TxtValue::Value(b"two")
    }) else {
    fail("updated snapshot invariant")
  }
  engine.advance(2100)
  guard engine.stats().cached_records == 0 && engine.snapshots().is_empty() else {
    fail("TTL cleanup invariant")
  }
  let dropped = engine.dropped_events()
  engine.close()
  while engine.poll_event() is Some(_) {
    ()
  }
  let closed_stats = engine.stats()
  guard closed_stats.cached_records == 0 &&
    closed_stats.services == 0 &&
    closed_stats.subscriptions == 0 &&
    closed_stats.query_jobs == 0 &&
    closed_stats.queued_questions == 0 &&
    closed_stats.queued_datagrams == 0 &&
    closed_stats.queued_events == 0 else {
    fail("closed engine retained state")
  }
  dropped
}

///|
async fn main {
  let args = @env.args()
  guard args.length() == 2 else {
    fail("usage: resource_soak <wall-clock-seconds>")
  }
  let seconds = @string.parse_int(args[1])
  guard seconds >= 1 && seconds <= 3600 else {
    fail("duration must be 1..3600 seconds")
  }
  let input = workload()
  for _ in 0..<20 {
    let _ = cycle(input)
  }
  let initial_rss = rss()
  let initial_handles = handles()
  guard initial_rss > 0 && initial_handles >= 0 else {
    fail("resource probes unavailable")
  }
  let mut peak_rss = initial_rss
  let mut peak_handles = initial_handles
  let mut cycles = 0
  let mut expected_drops = 0L
  let started = @transport.monotonic_ms()
  let mut progress = started
  while @transport.monotonic_ms() - started < seconds.to_int64() * 1000L {
    expected_drops += cycle(input)
    cycles += 1
    peak_rss = peak_rss.max(rss())
    peak_handles = peak_handles.max(handles())
    if @transport.monotonic_ms() - progress >= 30000L {
      println(
        Json::object({
          "progress_cycles": Json(cycles),
          "elapsed_ms": Json(@transport.monotonic_ms() - started),
          "rss_bytes": Json(rss()),
        }).stringify(),
      )
      progress = @transport.monotonic_ms()
    }
    @async.sleep(20)
  }
  let final_rss = rss()
  let final_handles = handles()
  guard final_rss - initial_rss < 32L * 1024L * 1024L &&
    final_handles - initial_handles <= 8L else {
    fail("resource growth exceeded bounded observation budget")
  }
  println(
    Json::object({
      "passed": Json(true),
      "duration_ms": Json(@transport.monotonic_ms() - started),
      "cycles": Json(cycles),
      "services_per_cycle": Json(50),
      "duplicate_packets_per_cycle": Json(5),
      "cache_peak_records": Json(201),
      "snapshot_resync_cycles": Json(cycles),
      "intentional_queue_drops": Json(expected_drops),
      "initial_rss_bytes": Json(initial_rss),
      "peak_rss_bytes": Json(peak_rss),
      "final_rss_bytes": Json(final_rss),
      "initial_handles": Json(initial_handles),
      "peak_handles": Json(peak_handles),
      "final_handles": Json(final_handles),
      "all_closed_state_counts_zero": Json(true),
    }).stringify(),
  )
}
