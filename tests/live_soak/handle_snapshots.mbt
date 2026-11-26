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
