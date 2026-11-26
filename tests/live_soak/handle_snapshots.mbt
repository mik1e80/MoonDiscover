///|
#borrow(output)
extern "C" fn handles_into(output : FixedArray[Byte], size : Int32) -> Int32 = "moondiscover_probe_snapshot"

///|
fn handle_snapshot() -> Json raise {
  let buffer : FixedArray[Byte] = FixedArray::make(65536, 0)
  let length = handles_into(buffer, buffer.length())
  guard length >= 2 && length <= buffer.length() else {
    fail("Windows process handle snapshot failed: \{length}")
  }
  @json.parse(@utf8.decode(Bytes::makei(length, i => buffer[i])))
}

///|
async fn snapshot_phase(
  phases : Map[String, Json],
  name : String,
  path~ : String = ".tools/live-soak-handles.json",
) -> Unit {
  let before = handles()
  let entries = handle_snapshot()
  phases[name] = Json::object({
    "count_before": Json(before.to_double()),
    "count_after": Json(handles().to_double()),
    "entries": entries,
  })
  @fs.write_file(path, Json::object(phases).stringify(indent=2))
}

///|
async fn fs_worker_control() -> Unit {
  let path = ".tools/live-soak-fs-control.json"
  let phases : Map[String, Json] = Map([])
  let _ = handle_snapshot()
  @fs.write_file(".tools/live-soak-fs-control-warmup.txt", "warmup")
  @async.sleep(100)
  snapshot_phase(phases, "warm_baseline", path~)
  @async.with_task_group(group => {
    for i in 1..<=3 {
      group.spawn_bg(() => {
        @fs.write_file(".tools/live-soak-fs-control-\{i}.txt", "control")
      })
    }
  })
  @async.sleep(1000)
  snapshot_phase(phases, "after_three_concurrent_writes", path~)
}
