///|
#borrow(executable, trace, metrics)
extern "C" fn supervise(
  executable : Bytes,
  trace : Bytes,
  wall_ms : Int32,
  memory_mib : Int32,
  cpu_seconds : Int32,
  metrics : FixedArray[Int64],
) -> Int32 = "moondiscover_guard_replay"

///|
async fn main {
  let args = @env.args()
  guard args.length() == 6 else {
    fail(
      "usage: replay_guard <trusted-native-cli> <trace> <wall-ms 10..60000> <memory-MiB 32..1024> <cpu-seconds 1..60>",
    )
  }
  let wall = @string.parse_int(args[3])
  let memory = @string.parse_int(args[4])
  let cpu = @string.parse_int(args[5])
  guard wall >= 10 &&
    wall <= 60000 &&
    memory >= 32 &&
    memory <= 1024 &&
    cpu >= 1 &&
    cpu <= 60 else {
    fail("invalid process budget")
  }
  let executable = @fs.realpath(args[1])
  let trace = @fs.realpath(args[2])
  let metrics = FixedArray::make(3, 0L)
  let code = supervise(
    @utf8.encode(executable),
    @utf8.encode(trace),
    wall,
    memory,
    cpu,
    metrics,
  )
  println(
    Json::object({
      "child_exit": Json(code),
      "passed": Json(code == 0),
      "wall_ms": Json(metrics[0].to_double()),
      "peak_rss_or_commit_bytes": Json(metrics[1].to_double()),
      "timed_out": Json(metrics[2] == 1L),
      "cpu_limited": Json(metrics[2] == 2L),
      "output": Json("discarded; this command reports resource results only"),
    }).stringify(),
  )
  guard code == 0 else { fail("guarded replay did not complete successfully") }
}
