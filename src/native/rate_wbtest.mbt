///|
test "smoke: source quotas remain bounded under spoofed IP churn" {
  assert_true(
    try {
      let _ = ReceiveBudget::new(-1, 64, 128)
      false
    } catch {
      InvalidArgument(_) => true
      _ => false
    },
  )
  let budget = ReceiveBudget::new(100, 2, 2)
  assert_true(budget.allow(1U, 0))
  assert_true(budget.allow(1U, 0))
  assert_false(budget.allow(1U, 0))
  assert_true(budget.allow(2U, 0))
  assert_false(budget.allow(3U, 0))
  assert_eq(budget.sources.length(), 2)
  assert_true(budget.allow(3U, 1000))
  assert_eq(budget.sources.length(), 1)
  assert_eq(budget.source_dropped, 2L)
}
