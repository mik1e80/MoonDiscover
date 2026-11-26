///|
async fn timed_pair(
  ip : UInt32,
  service : @dnssd.DnsName,
  seconds : Int32,
  round : Int32,
  phases : Map[String, Json],
) -> Json {
  let path = ".tools/live-soak-hourly-handles.json"
  let before = handles()
  let first = @native.Browser::open(ip)
  defer first.close()
  let second = @native.Browser::open(ip)
  defer second.close()
  let _ = first.browse(service)
  let _ = second.browse(service)
  snapshot_phase(phases, "round_\{round}_open", path~)
  let start = @native.monotonic_ms()
  let samples : Array[Json] = []
  let mut events = 0
  let mut previous = 0L
  let mut gap = 0L
  let mut sample_at = 0L
  let deadline = seconds.to_int64() * 1000L
  while @native.monotonic_ms() - start < deadline {
    events += first.poll(timeout_ms=0).length() +
      second.poll(timeout_ms=0).length()
    let elapsed = @native.monotonic_ms() - start
    gap = gap.max(elapsed - previous)
    previous = elapsed
    if elapsed >= sample_at {
      samples.push(sample_process(first, second, elapsed, events, 2))
      @fs.write_file(
        ".tools/live-soak-hourly-progress.json",
        Json::object({ "round": Json(round), "samples": Json::array(samples) }).stringify(
          indent=2,
        ),
      )
      sample_at += 600000L
    }
    @async.sleep(10)
  }
  let elapsed = @native.monotonic_ms() - start
  samples.push(sample_process(first, second, elapsed, events, 2))
  snapshot_phase(phases, "round_\{round}_before_close", path~)
  first.close()
  second.close()
  let closed = handles()
  let records = first.engine_stats().cached_records +
    second.engine_stats().cached_records
  @async.sleep(1000)
  let settled = handles()
  snapshot_phase(phases, "round_\{round}_closed", path~)
  guard before > 0L && closed > 0L && settled > 0L else {
    fail("handle measurement unavailable")
  }
  Json::object({
    "round": Json(round),
    "actual_ms": Json(elapsed.to_double()),
    "max_poll_gap_ms": Json(gap.to_double()),
    "before_open": Json(before.to_double()),
    "after_close": Json(closed.to_double()),
    "settled_after_1s": Json(settled.to_double()),
    "rss_after_close_bytes": Json(rss().to_double()),
    "cache_after_close": Json(records),
    "samples": Json::array(samples),
  })
}

///|
async fn hourly_reopen(
  ip : UInt32,
  service : @dnssd.DnsName,
  rounds : Int32,
  seconds : Int32,
) -> Unit {
  guard rounds >= 1 && rounds <= 6 && seconds >= 10 && seconds <= 3600 else {
    fail("expected 1..6 rounds of 10..3600 seconds")
  }
  let phases : Map[String, Json] = Map([])
  let _ = handle_snapshot()
  let warmup = @native.Browser::open(ip)
  let _ = warmup.poll(timeout_ms=0)
  warmup.close()
  @async.sleep(1)
  snapshot_phase(
    phases,
    "warm_baseline",
    path=".tools/live-soak-hourly-handles.json",
  )
  let results : Array[Json] = []
  for round in 1..<=rounds {
    let result = timed_pair(ip, service, seconds, round, phases)
    results.push(result)
    let report = Json::object({
      "requested_rounds": Json(rounds),
      "seconds_per_round": Json(seconds),
      "rounds_completed": Json(results.length()),
      "rounds": Json::array(results),
    })
    @fs.write_file(
      ".tools/live-soak-hourly-report.json",
      report.stringify(indent=2) + "\n",
    )
    guard result is { "cache_after_close": 0, .. } else {
      fail("cache retained after close")
    }
    println("completed round \{round}/\{rounds}")
  }
}
