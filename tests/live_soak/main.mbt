///|
extern "C" fn rss() -> Int64 = "moondiscover_probe_rss"

///|
extern "C" fn handles() -> Int64 = "moondiscover_probe_handles"

///|
async fn main {
  let args = @env.args()
  guard args.length() == 3 else {
    fail("usage: live_soak <active-ipv4> <seconds 1..21600>")
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
  let samples : Array[Json] = []
  let first = @native.Browser::open(ip)
  let second = @native.Browser::open(ip)
  defer first.close()
  defer second.close()
  let service = @dnssd.DnsName::parse("_mdprobe._tcp.local.")
  let _ = first.browse(service)
  let _ = second.browse(service)
  let mut sample_at = 0L
  let mut events = 0
  while @native.monotonic_ms() - origin < seconds.to_int64() * 1000L {
    events += first.poll(timeout_ms=0).length() +
      second.poll(timeout_ms=0).length()
    let elapsed = @native.monotonic_ms() - origin
    if elapsed >= sample_at {
      let stats = first.engine_stats()
      samples.push(
        Json::object({
          "at_ms": Json(elapsed.to_double()),
          "rss_bytes": Json(rss().to_double()),
          "handles_or_fds": Json(handles().to_double()),
          "services": Json(stats.services),
          "cached_records": Json(stats.cached_records),
          "query_jobs": Json(stats.query_jobs),
          "dropped_events": Json(stats.dropped_events.to_double()),
          "rate_dropped": Json(stats.rate_dropped.to_double()),
          "network_errors": Json(0),
          "interface_index": Json(first.interface_index),
          "events": Json(events),
        }),
      )
      @fs.write_file(
        ".tools/live-soak-progress.json",
        Json(samples).stringify(indent=2),
      )
      sample_at += 600000L
    }
    @async.sleep(10)
  }
  first.close()
  second.close()
  assert_eq(
    first.engine_stats().cached_records + second.engine_stats().cached_records,
    0,
  )
  assert_eq(handles(), initial_handles)
  let report = Json::object({
    "passed": Json(true),
    "requested_seconds": Json(seconds),
    "actual_ms": Json((@native.monotonic_ms() - origin).to_double()),
    "samples": Json(samples),
    "final_rss_bytes": Json(rss().to_double()),
    "final_handles_or_fds": Json(handles().to_double()),
    "closed_both": Json(true),
    "recovery": Json(
      "transport errors fail this observation; this test does not claim automatic migration or cross-device verification",
    ),
  })
  @fs.write_file(".tools/live-soak-report.json", report.stringify(indent=2))
  println(report.stringify())
}
