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
  let config = depth => {
    "{\"kind\":\"config\",\"format\":1,\"seed\":1,\"at_ms\":0,\"extra\":" +
    "[".repeat(depth) +
    "0" +
    "]".repeat(depth) +
    "}"
  }
  let replay = @replay.Replay::from_config(config(8))
  assert_eq(replay.step_line(config(8)).length(), 1)
  let escaped_brackets = Json("\\\"" + "[".repeat(20) + "{").stringify()
  let string_config = "{\"kind\":\"config\",\"format\":1,\"seed\":1,\"at_ms\":0,\"extra\":" +
    escaped_brackets +
    "}"
  let from_string = @replay.Replay::from_config(string_config)
  assert_eq(from_string.step_line(string_config).length(), 1)
  let over_budget = config(20)
  let from_config = Ok(@replay.Replay::from_config(over_budget)) catch {
    error => Err(error)
  }
  assert_true(from_config is Err(_))
  let fresh = @replay.Replay::new(seed=1U)
  let stepped = Ok(fresh.step_line(over_budget)) catch { error => Err(error) }
  assert_true(stepped is Err(_))
}
