///|
async fn main {
  let args = @env.args()
  guard args.length() == 2 else {
    fail("usage: nsec_probe <native recorded trace>")
  }
  guard @fs.file_size(args[1]) <= 8388608L else { fail("trace budget") }
  let trace = @fs.read_file(args[1]).text()
  let replay = @replay.Replay::from_config(
    trace.split("\n").next().unwrap().to_owned(),
  )
  let mut records = 0
  let mut negatives = 0
  for line in trace.split("\n") {
    let line = line.trim().to_owned()
    if line.is_empty() {
      continue
    }
    let frame = @json.parse(line)
    let _ = replay.step_line(line)
    if frame
      is {
        "kind": "packet",
        "scope": String(scope),
        "packet_hex": String(hex),
        ..
      } {
      let message = @wire.decode(@model.bytes_from_hex(hex))
      for record in message.records {
        if record.data is @wire.Nsec(_, bitmap) {
          records += 1
          for rr_type in [1, 16, 28, 33] {
            if !@wire.nsec_contains(bitmap, rr_type) &&
              replay.engine.is_negative(scope, record.name, rr_type) {
              negatives += 1
            }
          }
        }
      }
    }
  }
  guard records > 0 && negatives > 0 else {
    fail("no usable independent NSEC in recorded UDP trace")
  }
  println(
    Json::object({
      "passed": true,
      "nsec_records": records,
      "negative_observations": negatives,
      "trace": args[1],
      "limits": "independent publisher trace received by Native; reanalysis uses Engine Replay, not a second decoder",
    }).stringify(),
  )
}
