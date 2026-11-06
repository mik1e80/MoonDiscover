///|
test "smoke: query pressure rotates capacity without traffic or subscription churn starvation" {
  let engine = @engine.Engine::new(query_capacity=1)
  let names = [
    "_http._tcp.local.", "_ssh._tcp.local.", "_ipp._tcp.local.", "_sftp._tcp.local.",
  ]
  for name in names {
    let _ = engine.browse(@model.DnsName::parse(name), "link", 0)
  }
  let sent : Array[String] = []
  for second in 0..<8 {
    let now = second.to_int64() * 1000L
    engine.advance(now)
    engine.advance(now + 120L)
    while engine.poll_outbound() is Some(q) {
      sent.push(q.name.to_presentation())
    }
    assert_eq(engine.stats().query_jobs, 1)
    assert_true(engine.next_deadline() is Some(_))
  }
  for name in names {
    assert_true(sent.contains(name))
  }
  assert_eq(engine.stats().deferred_queries, 3)
  engine.close()
  assert_eq(engine.stats().deferred_queries, 0)
  assert_true(engine.next_deadline() is None)
}
