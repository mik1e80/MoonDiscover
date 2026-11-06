///|
fn state_records(slot : Int32) -> Array[@wire.Record] raise {
  let service = @model.DnsName::parse("_state._tcp.local.")
  let instance = @model.DnsName::parse("peer\{slot}._state._tcp.local.")
  let host = @model.DnsName::parse("shared.local.")
  [
    {
      name: service,
      rr_type: 12,
      rr_class: 1,
      ttl: 2U,
      cache_flush: false,
      data: @wire.Ptr(instance),
      section: @wire.Answer,
    },
    {
      name: instance,
      rr_type: 33,
      rr_class: 1,
      ttl: 2U,
      cache_flush: true,
      data: @wire.Srv(0, slot, 8000 + slot, host),
      section: @wire.Additional,
    },
    {
      name: instance,
      rr_type: 16,
      rr_class: 1,
      ttl: 2U,
      cache_flush: true,
      data: @wire.Txt(@model.TxtRecord::from_entries([b"v=1"])),
      section: @wire.Authority,
    },
    {
      name: host,
      rr_type: 1,
      rr_class: 1,
      ttl: 2U,
      cache_flush: true,
      data: @wire.A(b"\x0a\x00\x00\x01"),
      section: @wire.Additional,
    },
  ]
}

///|
fn state_checks(target : String, seed : UInt32, cases : Int32) -> Unit raise {
  guard target == "cache" || target == "engine" else {
    fail("target must be wire/cache/engine")
  }
  let mut rng = seed
  fn random(n : Int32) -> Int32 {
    rng = rng * 1664525U + 1013904223U
    (rng % n.reinterpret_as_uint()).reinterpret_as_int()
  }
  let cache = @cache.RecordCache::new(capacity=8)
  let mut engine = @engine.Engine::new(
    cache_capacity=12,
    service_capacity=3,
    event_capacity=2,
    query_capacity=2,
  )
  let subscriptions : Array[Int32] = []
  let mut now = 0L
  for i in 0..<cases {
    now += random(250).to_int64()
    let slot = random(8)
    let action = random(6)
    let records = state_records(slot)
    println(
      Json::object({
        "case": Json(i),
        "seed": Json(seed),
        "target": Json(target),
        "action": Json(action),
        "slot": Json(slot),
        "at_ms": Json(now.to_double()),
      }).stringify(),
    )
    if target == "cache" {
      let original = records[3]
      let name = @model.DnsName::parse("h\{slot}.local.")
      let old = cache.len()
      let record = {
        ..original,
        name,
        ttl: if action == 0 {
          0U
        } else if action == 1 {
          4294967295U
        } else {
          1U
        },
        data: if action == 5 {
          @wire.A(b"bad")
        } else {
          original.data
        },
      }
      let _ = cache.ingest(
        if slot % 2 == 0 {
          "a"
        } else {
          "b"
        },
        { id: slot, flags: 0x8200, questions: [], records: [record], },
        now,
      ) catch {
        _ => {
          assert_eq(cache.len(), old)
          []
        }
      }
      let _ = cache.advance(now)
      assert_true(cache.len() <= 8)
      for slot in 0..<8 {
        let values = cache.records(
          if slot % 2 == 0 {
            "a"
          } else {
            "b"
          },
          @model.DnsName::parse("h\{slot}.local."),
          1,
        )
        assert_true(values.length() <= 1)
        for value in values {
          assert_true(
            value.expires_at > now &&
            value.record.data is @wire.A(bytes) &&
            bytes.length() == 4,
          )
        }
      }
    } else {
      match action {
        0 =>
          if subscriptions.length() < 8 {
            subscriptions.push(engine.browse(records[0].name, "link", now))
          }
        1 =>
          if !subscriptions.is_empty() {
            engine.cancel(
              subscriptions.remove(random(subscriptions.length())),
              now,
            )
          }
        2 | 3 | 4 => {
          let before = engine.snapshots().map(@replay.snapshot_json)
          let input = if action == 2 {
            records
          } else if action == 3 {
            [{ ..records[0], ttl: 0U, }]
          } else {
            [records[0], { ..records[3], data: @wire.A(b"bad"), }]
          }
          engine.ingest_message(
            { id: 7, flags: 0x8200, questions: [], records: input, },
            "link",
            now,
          ) catch {
            _ =>
              assert_eq(engine.snapshots().map(@replay.snapshot_json), before)
          }
        }
        _ => {
          engine.close()
          assert_eq(
            engine.stats().cached_records +
            engine.stats().services +
            engine.stats().subscriptions,
            0,
          )
          subscriptions.clear()
          engine = @engine.Engine::new(
            cache_capacity=12,
            service_capacity=3,
            event_capacity=2,
            query_capacity=2,
          )
        }
      }
      engine.advance(now)
      for _ in 0..<8 {
        if engine.poll_outbound() is None {
          break
        }
      }
      let view = engine.state_view()
      assert_true(view.snapshots.length() <= 3)
      assert_true(
        engine.stats().cached_records <= 12 &&
        engine.stats().queued_events <= 2 &&
        engine.stats().query_jobs <= 2,
      )
      if random(2) == 0 {
        while engine.poll_envelope() is Some(e) {
          assert_true(e.sequence <= view.sequence)
        }
      }
    }
  }
  engine.close()
  println(
    Json::object({
      "passed": Json(true),
      "seed": Json(seed),
      "cases": Json(cases),
      "target": Json(target),
    }).stringify(),
  )
}
