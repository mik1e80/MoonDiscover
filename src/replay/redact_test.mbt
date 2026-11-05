///|
test "smoke: redacted exports whitelist fields and remove publisher and diagnostic payloads" {
  let event : Json = {
    "event": "resolved",
    "scope": "private-network",
    "packet_hex": "secret",
    "service": {
      "complete": true,
      "instance": "private-name",
      "target": "internal.local.",
      "port": 443,
      "addresses": ["192.168.1.7"],
      "srv_candidates": [{ "target": "private" }],
      "txt_entries_hex": ["secret"],
    },
  }
  assert_eq(@replay.redacted_output(event), {
    "event": "resolved",
    "redacted": true,
    "complete": true,
    "address_count": 1,
    "srv_candidate_count": 1,
  })
  assert_eq(
    @replay.redacted_output({
      "event": "diagnostic",
      "code": "secret",
      "detail": "private",
    }),
    { "event": "diagnostic", "redacted": true },
  )
  assert_eq(@replay.redacted_output({ "event": "attacker-controlled" }), {
    "event": "unknown",
    "redacted": true,
  })
}
