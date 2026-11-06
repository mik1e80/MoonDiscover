///|
test "smoke: clock failures and regressions preserve stable transport classification" {
  assert_eq(validate_elapsed(100L, 20L, 120L), 20L)
  for current in [-1L, 99L, 119L] {
    assert_true(
      try {
        let _ = validate_elapsed(100L, 20L, current)
        false
      } catch {
        e => e.diagnostic_code() == "socket_error"
      },
    )
  }
}
