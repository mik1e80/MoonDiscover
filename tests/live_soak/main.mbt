///|
extern "C" fn rss() -> Int64 = "moondiscover_probe_rss"

///|
extern "C" fn handles() -> Int64 = "moondiscover_probe_handles"

///|
fn sample_browser(browser : @native.Browser) -> Json {
  let stats = browser.engine_stats()
  Json::object({
    "services": Json(stats.services),
    "complete_services": Json(
      browser.snapshots().filter(s => s.complete).length(),
    ),
    "cached_records": Json(stats.cached_records),
    "query_jobs": Json(stats.query_jobs),
    "dropped_events": Json(stats.dropped_events.to_double()),
    "rate_dropped": Json(stats.rate_dropped.to_double()),
    "interface_index": Json(browser.interface_index),
  })
}

///|
fn sample_process(
  first : @native.Browser,
  second : @native.Browser,
  elapsed : Int64,
  events : Int32,
  expected : Int32,
) -> Json raise {
  let resident = rss()
  let descriptors = handles()
  guard resident > 0L && descriptors > 0L else {
    fail("resource measurement unavailable")
  }
  let primary = sample_browser(first)
  let peer = sample_browser(second)
  if expected > 0 && elapsed >= 10000L {
    guard primary is { "complete_services": Number(a, ..), .. } &&
      peer is { "complete_services": Number(b, ..), .. } &&
      a >= expected.to_double() &&
      b >= expected.to_double() else {
      fail(
        "fixture services were not complete in both Browsers: " +
        primary.stringify() +
        " " +
        peer.stringify(),
      )
    }
  }
  // Keep the existing first-Browser counters at the top level for old readers.
  guard primary is Object(fields) else { fail("invalid Browser sample") }
  fields["at_ms"] = Json(elapsed.to_double())
  fields["rss_bytes"] = Json(resident.to_double())
  fields["handles_or_fds"] = Json(descriptors.to_double())
  fields["network_errors"] = Json(0)
  fields["events"] = Json(events)
  fields["second_browser"] = peer
  primary
}

///|
async fn main {
  let args = @env.args()
  guard args.length() == 3 || args.length() == 5 else {
    fail(
      "usage: live_soak <active-ipv4> <seconds 1..21600> [<service-type> <minimum-complete-services>]",
    )
  }
  let seconds = @string.parse_int(args[2])
  guard seconds >= 1 && seconds <= 21600 else {
    fail("duration outside 1..21600")
  }
  let ip = @socket.Addr::parse(args[1] + ":0").ip()
  @fs.write_file(
    ".tools/live-soak-report.json", "{\"passed\":false,\"status\":\"started\"}",
  )
  let warmup = @native.Browser::open(ip)
  let _ = warmup.poll(timeout_ms=0)
  warmup.close()
  @async.sleep(1)
  let origin = @native.monotonic_ms()
  let initial_handles = handles()
  let initial_rss = rss()
  guard initial_handles > 0L && initial_rss > 0L else {
    fail("resource baseline unavailable")
  }
  let samples : Array[Json] = []
  let first = @native.Browser::open(ip)
  let second = @native.Browser::open(ip)
  defer first.close()
  defer second.close()
  let service = @dnssd.DnsName::parse(
    if args.length() == 5 {
      args[3]
    } else {
      "_mdprobe._tcp.local."
    },
  )
  let expected = if args.length() == 5 { @string.parse_int(args[4]) } else { 0 }
  guard expected >= 0 else { fail("negative fixture service count") }
  let _ = first.browse(service)
  let _ = second.browse(service)
  let mut sample_at = 0L
  let mut events = 0
  let mut last_poll = 0L
  let mut max_poll_gap = 0L
  while @native.monotonic_ms() - origin < seconds.to_int64() * 1000L {
    events += first.poll(timeout_ms=0).length() +
      second.poll(timeout_ms=0).length()
    let elapsed = @native.monotonic_ms() - origin
    max_poll_gap = max_poll_gap.max(elapsed - last_poll)
    last_poll = elapsed
    if elapsed >= sample_at {
      samples.push(sample_process(first, second, elapsed, events, expected))
      @fs.write_file(
        ".tools/live-soak-progress.json",
        Json(samples).stringify(indent=2),
      )
      sample_at += 600000L
    }
    @async.sleep(10)
  }
  let elapsed = @native.monotonic_ms() - origin
  samples.push(sample_process(first, second, elapsed, events, expected))
  first.close()
  second.close()
  assert_eq(
    first.engine_stats().cached_records + second.engine_stats().cached_records,
    0,
  )
  assert_eq(handles(), initial_handles)
  let final_rss = rss()
  guard final_rss > 0L else { fail("final RSS unavailable") }
  let report = Json::object({
    "passed": Json(true),
    "requested_seconds": Json(seconds),
    "actual_ms": Json(elapsed.to_double()),
    "samples": Json(samples),
    "service_type": Json(service.to_presentation()),
    "minimum_complete_services_per_browser": Json(expected),
    "warmup_rss_bytes": Json(initial_rss.to_double()),
    "warmup_handles_or_fds": Json(initial_handles.to_double()),
    "max_poll_gap_ms": Json(max_poll_gap.to_double()),
    "final_rss_bytes": Json(final_rss.to_double()),
    "final_handles_or_fds": Json(handles().to_double()),
    "closed_both": Json(true),
    "recovery": Json(
      "transport errors fail this observation; this test does not claim automatic migration or cross-device verification",
    ),
  })
  @fs.write_file(".tools/live-soak-report.json", report.stringify(indent=2))
  println(report.stringify())
}
