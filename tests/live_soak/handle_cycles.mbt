///|
fn complete_instances(browser : @native.Browser) -> Int32 {
  browser.snapshots().filter(s => s.complete).length()
}

///|
async fn cycle_pair(
  ip : UInt32,
  service : @dnssd.DnsName,
  round : Int32,
  capture : Bool,
  phases : Map[String, Json],
) -> Json {
  let before = handles()
  let first = @native.Browser::open(ip)
  defer first.close()
  let second = @native.Browser::open(ip)
  defer second.close()
  let _ = first.browse(service)
  let _ = second.browse(service)
  let start = @native.monotonic_ms()
  while @native.monotonic_ms() - start < 5000L {
    let _ = first.poll(timeout_ms=0)
    let _ = second.poll(timeout_ms=0)
    if complete_instances(first) >= 2 && complete_instances(second) >= 2 {
      break
    }
    @async.sleep(10)
  }
  let complete = (complete_instances(first), complete_instances(second))
  guard complete.0 >= 2 && complete.1 >= 2 else {
    fail("both cycle Browsers must resolve two fixture services")
  }
  let active = handles()
  if capture {
    snapshot_phase(
      phases,
      "cycle_\{round}_loaded",
      path=".tools/live-soak-cycle-handles.json",
    )
  }
  first.close()
  second.close()
  let closed = handles()
  let records = first.engine_stats().cached_records +
    second.engine_stats().cached_records
  @async.sleep(100)
  let settled = handles()
  guard before > 0L && active > 0L && closed > 0L && settled > 0L else {
    fail("handle measurements unavailable")
  }
  if capture {
    snapshot_phase(
      phases,
      "cycle_\{round}_closed",
      path=".tools/live-soak-cycle-handles.json",
    )
  }
  Json::object({
    "round": Json(round),
    "before_open": Json(before.to_double()),
    "while_loaded": Json(active.to_double()),
    "after_close": Json(closed.to_double()),
    "settled_after_100ms": Json(settled.to_double()),
    "cache_after_close": Json(records),
    "complete_instances": Json([complete.0, complete.1]),
  })
}

///|
async fn handle_cycles(
  ip : UInt32,
  service : @dnssd.DnsName,
  rounds : Int32,
) -> Unit {
  guard rounds >= 1 && rounds <= 100 else { fail("expected 1..100 cycles") }
  let path = ".tools/live-soak-cycle-handles.json"
  let _ = handle_snapshot()
  let warmup = @native.Browser::open(ip)
  let _ = warmup.poll(timeout_ms=0)
  warmup.close()
  @async.sleep(1)
  let phases : Map[String, Json] = Map([])
  snapshot_phase(phases, "warm_baseline", path~)
  let results : Array[Json] = []
  for round in 1..<=rounds {
    results.push(
      cycle_pair(ip, service, round, round == 1 || round == rounds, phases),
    )
  }
  let report = Json::object({
    "rounds": Json(rounds),
    "samples": Json::array(results),
  })
  @fs.write_file(".tools/live-soak-cycles.json", report.stringify(indent=2))
  println(report.stringify())
}
