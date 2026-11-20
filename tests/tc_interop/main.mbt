///|
fn tc_burst(
  service : @model.DnsName,
  known_answers : Array[@wire.Record],
) -> (Bytes, Bytes) raise {
  let head = @wire.qm_query(service, 12).to_array()
  head[2] = b'\x02'
  let full = @wire.query_with_answers(service, 12, known_answers)
  let tail = Array::make(12, b'\x00')
  tail[7] = known_answers.length().to_byte()
  for i in head.length()..<full.length() {
    tail.push(full[i])
  }
  let first = Bytes::makei(head.length(), i => head[i])
  let last = Bytes::makei(tail.length(), i => tail[i])
  let a = @probe.independent_packet(first)
  let b = @probe.independent_packet(last)
  guard a.flags == 0x0200 &&
    a.questions.length() == 1 &&
    a.answers.is_empty() &&
    b.flags == 0 &&
    b.questions.is_empty() &&
    b.answers.length() == known_answers.length() else {
    fail("incorrect TC experiment fixture")
  }
  (first, last)
}

///|
fn nullable_ms(value : Int64?) -> Json {
  match value {
    Some(ms) => Json(ms.to_double())
    None => Json::null()
  }
}

///|
fn observation(
  seen : Map[Bytes, Int64],
  known : @model.DnsName,
  unknown : @model.DnsName,
  tail_at : Int64?,
) -> Json {
  let known_at = seen.get(known.canonical_key())
  let unknown_at = seen.get(unknown.canonical_key())
  let first_at = match (known_at, unknown_at) {
    (Some(a), Some(b)) => Some(a.min(b))
    (Some(a), None) | (None, Some(a)) => Some(a)
    (None, None) => None
  }
  Json::object({
    "known_ptr_ms": nullable_ms(known_at),
    "unknown_ptr_ms": nullable_ms(unknown_at),
    "first_ptr_ms": nullable_ms(first_at),
    "known_ptr_omitted_with_unknown_observed": Json(
      known_at is None && unknown_at is Some(_),
    ),
    "first_ptr_before_tail": match (first_at, tail_at) {
      (Some(first), Some(tail)) => Json(first < tail)
      _ => Json::null()
    },
    "first_ptr_in_400_to_500_ms": match first_at {
      Some(ms) => Json(ms >= 400L && ms <= 500L)
      None => Json::null()
    },
  })
}

///|
async fn main {
  let args = @env.args()
  guard args.length() == 2 else { fail("usage: tc_interop <IPv4>") }
  let addr = @socket.Addr::parse(args[1] + ":0")
  guard !addr.is_ipv6() else { fail("IPv4 required") }
  let socket = @native.MulticastSocket::open(addr.ip())
  defer socket.close()
  let service = @model.DnsName::parse("_md-tcproof._tcp.local.")
  let names = ["av-known", "av-unknown", "zc-known", "zc-unknown"].map(label => {
    @model.DnsName::parse(label + "." + service.to_presentation())
  })
  let known_answers : Array[@wire.Record] = [names[0], names[2]].map(name => {
    name: service,
    rr_type: 12,
    rr_class: 1,
    ttl: 4500U,
    cache_flush: false,
    data: @wire.Ptr(name),
    section: @wire.Answer,
  })
  let (head, tail) = tc_burst(service, known_answers)
  let plain = @wire.qm_query(service, 12)
  let single = @wire.query_with_answers(service, 12, known_answers)
  let arms : Array[Json] = []
  let mut baseline = false
  for mode in ["plain", "single", "immediate_tail", "delayed_tail", "head_only"] {
    if mode != "plain" {
      @async.sleep(2100)
    }
    for _ in 0..<128 {
      if socket.receive(timeout_ms=0) is None {
        break
      }
    }
    let t0 = @native.monotonic_ms()
    let mut tail_at : Int64? = None
    match mode {
      "plain" => socket.send(plain)
      "single" => socket.send(single)
      "immediate_tail" => {
        socket.send(head)
        socket.send(tail)
        tail_at = Some(@native.monotonic_ms() - t0)
      }
      _ => socket.send(head)
    }
    let seen : Map[Bytes, Int64] = Map([])
    while @native.monotonic_ms() - t0 < 1050L {
      let elapsed = @native.monotonic_ms() - t0
      if mode == "delayed_tail" && tail_at is None && elapsed >= 250L {
        socket.send(tail)
        tail_at = Some(@native.monotonic_ms() - t0)
      }
      if socket.receive(timeout_ms=5) is Some(packet) {
        let received_at = @native.monotonic_ms() - t0
        if packet.source_port != 5353 || packet.destination_ipv4 != 0xe00000fbU {
          continue
        }
        let message = @wire.decode(packet.bytes) catch { _ => continue }
        if (message.flags & 0xf80f) != 0x8000 {
          continue
        }
        for record in message.records {
          if record.section is @wire.Answer &&
            record.rr_class == 1 &&
            record.ttl > 0 &&
            record.name.same_name(service) &&
            record.data is @wire.Ptr(target) &&
            names.any(n => n.same_name(target)) {
            let key = target.canonical_key()
            if !seen.contains(key) {
              seen[key] = received_at
            }
          }
        }
      }
    }
    if mode == "plain" {
      baseline = seen.length() == names.length()
    }
    arms.push(
      Json::object({
        "mode": Json(mode),
        "tail_sent_ms": nullable_ms(tail_at),
        "avahi": observation(seen, names[0], names[1], tail_at),
        "zeroconf": observation(seen, names[2], names[3], tail_at),
      }),
    )
  }
  let report = Json::object({
    "baseline_both_responders": Json(baseline),
    "arms": Json::array(arms),
    "scope": Json(
      "same Linux runner; two responder processes and implementations; results attributed by exclusively registered PTR targets",
    ),
  })
  println(report.stringify())
  guard baseline else {
    fail("plain query did not observe all four independent registrations")
  }
}
