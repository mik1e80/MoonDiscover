///|
test "smoke: bounded seeded names and hostile DNS bytes remain safe to decode" {
  let mut state = 0x7123abcdU
  fn next() -> UInt32 {
    state = state * 1664525U + 1013904223U
    state
  }
  for _ in 0..<256 {
    let labels : Array[Bytes] = []
    for _ in 0..<((next() % 4U).reinterpret_as_int() + 1) {
      let length = (next() % 20U).reinterpret_as_int() + 1
      labels.push(Bytes::makei(length, _ => (next() >> 24).to_byte()))
    }
    let name = @model.DnsName::from_labels(labels)
    let decoded = @wire.decode(@wire.qm_query(name, 12))
    assert_eq(decoded.questions[0].name.labels(), labels)
    let length = (next() % 512U).reinterpret_as_int()
    let bytes = Bytes::makei(length, _ => (next() >> 24).to_byte())
    let _ = @wire.decode(bytes) catch {
      _ => { id: 0, flags: 0, questions: [], records: [], }
    }
  }
  // A label followed by a backward pointer to that label creates a cycle.
  for bytes in [b"\x01a\xc0\x00", b"\xc0\xff", b"\xc0", b"\x3fshort"] {
    assert_true(
      try {
        let _ = @wire.decode_name(bytes, 0)
        false
      } catch {
        _ => true
      },
    )
  }
  // Independently written malformed SRV and TXT response lengths.
  for
    bytes in [
      b"\x00\x00\x84\x00\x00\x00\x00\x01\x00\x00\x00\x00\x00\x00\x21\x00\x01\x00\x00\x00\x78\x00\x06\x00\x00\x00\x00\x00\x50",
      b"\x00\x00\x84\x00\x00\x00\x00\x01\x00\x00\x00\x00\x00\x00\x10\x00\x01\x00\x00\x00\x78\x00\x02\x05x",
    ] {
    assert_true(
      try {
        let _ = @wire.decode(bytes)
        false
      } catch {
        _ => true
      },
    )
  }
}
