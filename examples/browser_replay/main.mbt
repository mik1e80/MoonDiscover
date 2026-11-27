///|
// Expose a plain string callback; all protocol work stays in the public Replay.
extern "js" fn install_replay(callback : (String) -> String) -> Unit =
  #| (callback) => { globalThis.moonDiscoverReplay = callback; }

///|
// Use the same parser budget for the initial config probe as for replay.
#warnings("-deprecated")
fn parse_first_command(line : String) -> Json raise @json.ParseError {
  @json.parse(line, max_nesting_depth=16, reject_duplicate_keys=true)
}

///|
fn replay_text(content : String) -> String {
  let mut source_line = 0
  let result = try {
    guard content.length() <= 8388608 &&
      @utf8.encode(content).length() <= 8388608 else {
      fail("input exceeds 8 MiB")
    }
    let commands : Array[(Int32, String)] = []
    for line in content.split("\n") {
      source_line += 1
      let text = line.trim().to_owned()
      if text != "" {
        guard commands.length() < 10000 else {
          fail("input exceeds 10000 frames")
        }
        commands.push((source_line, text))
      }
    }
    guard !commands.is_empty() else { fail("paste or load a JSONL recording") }
    source_line = commands[0].0
    guard commands[0].1.length() <= 32768 else {
      fail("line exceeds 32768 characters")
    }
    let first = parse_first_command(commands[0].1)
    let mut seed = Json(1)
    let replay = if first is { "kind": "config", "seed": value, .. } {
      seed = value
      @dnssd.Replay::from_config(commands[0].1)
    } else {
      @dnssd.Replay::new(seed=1U)
    }
    let output : Array[Json] = []
    for (line, command) in commands {
      source_line = line
      for event in replay.step_line(command) {
        guard output.length() < 20000 else {
          fail(
            "example output exceeds 20000 records; use the CLI for this trace",
          )
        }
        output.push(event)
      }
    }
    Json::object({
      "ok": Json(true),
      "frames": Json(commands.length()),
      "seed": seed,
      "outputs": Json::array(output),
    })
  } catch {
    error =>
      Json::object({
        "ok": Json(false),
        "line": Json(source_line),
        "error": Json("\{error}"),
      })
  }
  result.stringify()
}

///|
fn main {
  install_replay(replay_text)
}
