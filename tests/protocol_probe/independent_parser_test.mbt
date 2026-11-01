///|
test "smoke: independent parser validates emitted Known-Answer packets" {
  assert_eq(@protocol_probe.check_full_burst(), 260)
  assert_true(@protocol_probe.check_cancellation() > 0)
  @protocol_probe.check_oversize_fallback()
}
