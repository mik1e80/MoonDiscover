///|
fn rejected(replay : @replay.Replay, command : String) -> Bool {
  try {
    let _ = replay.step_line(command)
    false
  } catch {
    _ => true
  }
}

///|
test "smoke: Replay bounds cumulative frames input packets and output with terminal cleanup" {
  let browse = "{\"kind\":\"browse\",\"at_ms\":0,\"scope\":\"lab\",\"name\":\"_http._tcp.local.\"}"
  let advance = "{\"kind\":\"advance\",\"at_ms\":0}"
  let frames = @replay.Replay::new(max_frames=1)
  let _ = frames.step_line(browse)
  assert_true(rejected(frames, advance))
  assert_eq(frames.engine.stats().subscriptions, 0)
  assert_true(rejected(frames, advance))
  let input = @replay.Replay::new(max_input_bytes=advance.length() + 1)
  let _ = input.step_line(advance)
  assert_true(rejected(input, advance))
  let packet = "{\"kind\":\"packet\",\"at_ms\":0,\"scope\":\"lab\",\"packet_hex\":\"000084000000000000000000\"}"
  let packets = @replay.Replay::new(max_packet_bytes=12)
  let _ = packets.step_line(packet)
  assert_true(rejected(packets, packet))
  let events = @replay.Replay::new(max_output_events=1)
  let _ = events.step_line(browse)
  assert_true(rejected(events, browse))
  assert_eq(events.engine.stats().subscriptions, 0)
  let bytes = @replay.Replay::new(max_output_bytes=1)
  assert_true(rejected(bytes, browse))
  assert_eq(bytes.engine.stats().subscriptions, 0)
}

///|
test "smoke: oversized packet hex is rejected before decoding and valid input still works" {
  let replay = @replay.Replay::new()
  let oversized = "00".repeat(9001)
  assert_true(
    rejected(
      replay,
      "{\"kind\":\"packet\",\"at_ms\":0,\"scope\":\"lab\",\"packet_hex\":\"\{oversized}\"}",
    ),
  )
  assert_true(
    rejected(
      replay, "{\"kind\":\"packet\",\"at_ms\":0,\"scope\":\"lab\",\"packet_hex\":\"xy\"}",
    ),
  )
  assert_true(replay.step_line("{\"kind\":\"advance\",\"at_ms\":0}").is_empty())
}

///|
test "smoke: offline replay does not silently apply live packet rate limits" {
  let replay = @replay.Replay::new()
  for _ in 0..<300 {
    assert_true(
      replay
      .step_line(
        "{\"kind\":\"packet\",\"at_ms\":0,\"scope\":\"lab\",\"packet_hex\":\"000084000000000000000000\"}",
      )
      .is_empty(),
    )
  }
  assert_eq(replay.engine.stats().rate_dropped, 0L)
}
