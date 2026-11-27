///|
test "smoke: trace config restores full UInt32 seed and rejects mismatches" {
  let config = "{\"kind\":\"config\",\"format\":1,\"seed\":4294967295,\"at_ms\":0}"
  let replay = @replay.Replay::from_config(config)
  assert_eq(replay.step_line(config).length(), 1)
  let duplicate = try {
    let _ = replay.step_line(config)
    false
  } catch {
    _ => true
  }
  assert_true(duplicate)
  let wrong = @replay.Replay::new(seed=1U)
  let mismatch = try {
    let _ = wrong.step_line(config)
    false
  } catch {
    _ => true
  }
  assert_true(mismatch)
}

///|
test "smoke: replay keeps the JSON nesting budget" {
  let config = "{\"kind\":\"config\",\"format\":1,\"seed\":1,\"at_ms\":0,\"extra\":" +
    "[".repeat(20) +
    "0" +
    "]".repeat(20) +
    "}"
  let result = try? @replay.Replay::from_config(config)
  assert_true(result is Err(@json.DepthLimitExceeded))
  let replay = @replay.Replay::new(seed=1U)
  let result = try? replay.step_line(config)
  assert_true(result is Err(@json.DepthLimitExceeded))
}
