///|
async fn main {
  let args = @env.args()
  if args.length() == 3 && args[1] == "--oracle" {
    // Synthetic minimizer oracle, deliberately unrelated to DNS vulnerabilities.
    let hex = @fs.read_file(args[2]).text().trim().to_owned()
    if hex.find("425547") is Some(_) {
      fail("synthetic BUG sentinel")
    }
    return
  }
  guard args.length() == 4 else {
    fail("test child requires replay --file mode")
  }
  let mode = @fs.read_file(args[3]).text().trim()
  @fs.write_file(".tools/guard-probe-started", mode.to_owned())
  if mode == "stall" {
    @async.sleep(10000)
  } else if mode == "memory" {
    let held : Array[Bytes] = []
    for _ in 0..<128 {
      held.push(Bytes::make(8388608, b'x'))
    }
    println(held.length())
  } else if mode == "cpu" {
    let mut state = 1U
    for ;; {
      state = state * 1664525U + 1013904223U
      if state == 0U {
        println(state)
      }
    }
  } else {
    fail("unknown synthetic resource probe")
  }
}
