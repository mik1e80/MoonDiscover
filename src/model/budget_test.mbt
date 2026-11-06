///|
test "smoke: packet budget bounds bursts fractional refill and long pauses" {
  let budget = @model.PacketBudget::new(limit=2)
  assert_true(budget.allow(0))
  assert_true(budget.allow(0))
  assert_false(budget.allow(0))
  assert_false(budget.allow(499))
  assert_true(budget.allow(500))
  assert_false(budget.allow(500))
  assert_true(budget.allow(9223367741887480807L))
  assert_true(budget.allow(9223367741887480807L))
  assert_false(budget.allow(9223367741887480807L))
  assert_eq(budget.dropped(), 4L)
  assert_true(
    try {
      let _ = budget.allow(0)
      false
    } catch {
      _ => true
    },
  )
}
