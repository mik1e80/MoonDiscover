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
  if args.length() == 4 || args.length() == 5 {
    extended_probe(args[1], args[2], args[3], args.get(4))
    return
  }
  guard args.length() == 3 else {
    fail(
      "usage: tc_interop <IPv4> <second-source-IPv4> [third-source-IPv4] [fourth-source-IPv4]",
    )
  }
  let addr = @socket.Addr::parse(args[1] + ":0")
  let second = @socket.Addr::parse(args[2] + ":0")
  guard !addr.is_ipv6() && !second.is_ipv6() && addr.ip() != second.ip() else {
    fail("two distinct IPv4 addresses required")
  }
  let socket = @native.MulticastSocket::open(addr.ip())
  defer socket.close()
  let waiter = @native.MulticastSocket::open(second.ip())
  defer waiter.close()
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
  let modes = [
    "plain", "single", "immediate_tail", "delayed_tail", "head_only", "head_only",
    "head_only", "head_only", "head_only", "solo_tail", "two_queriers", "solo_tail",
    "two_queriers", "solo_tail", "two_queriers",
  ]
  for trial, mode in modes {
    if mode != "plain" {
      @async.sleep(2100)
    }
    for _ in 0..<128 {
      if socket.receive(timeout_ms=0) is None {
        break
      }
    }
    for _ in 0..<128 {
      if waiter.receive(timeout_ms=0) is None {
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
    let waiter_seen : Map[Bytes, Int64] = Map([])
    let mut waiter_at : Int64? = None
    let mut waiter_qm_observed = false
    let mut primary_head_observed = false
    let mut primary_tail_observed = false
    while @native.monotonic_ms() - t0 < 1050L {
      let elapsed = @native.monotonic_ms() - t0
      if mode == "delayed_tail" && tail_at is None && elapsed >= 250L {
        socket.send(tail)
        tail_at = Some(@native.monotonic_ms() - t0)
      }
      if (mode == "two_queriers" || mode == "solo_tail") &&
        tail_at is None &&
        elapsed >= 30L {
        if mode == "two_queriers" {
          waiter.send(plain)
          waiter_at = Some(@native.monotonic_ms() - t0)
        }
        socket.send(tail)
        tail_at = Some(@native.monotonic_ms() - t0)
      }
      if mode == "two_queriers" {
        for _ in 0..<16 {
          guard waiter.receive(timeout_ms=0) is Some(packet) else { break }
          record_answers(
            packet,
            @native.monotonic_ms() - t0,
            service,
            names,
            waiter_seen,
          )
        }
      }
      if socket.receive(timeout_ms=5) is Some(packet) {
        let received_at = @native.monotonic_ms() - t0
        if packet.source_ipv4 == second.ip() &&
          packet.bytes == plain &&
          primary_head_observed {
          waiter_qm_observed = true
        }
        if packet.source_ipv4 == addr.ip() && packet.bytes == head {
          primary_head_observed = true
        }
        if packet.source_ipv4 == addr.ip() &&
          packet.bytes == tail &&
          waiter_qm_observed {
          primary_tail_observed = true
        }
        record_answers(packet, received_at, service, names, seen)
      }
    }
    if mode == "plain" {
      baseline = seen.length() == names.length()
    }
    if mode == "two_queriers" {
      guard primary_head_observed && waiter_qm_observed && primary_tail_observed else {
        fail(
          "could not verify distinct querier datagrams and the TC burst on the link",
        )
      }
    }
    arms.push(
      Json::object({
        "mode": Json(mode),
        "trial": Json(trial + 1),
        "query_start_monotonic_ms": Json(t0.to_double()),
        "tail_sent_ms": nullable_ms(tail_at),
        "avahi": observation(seen, names[0], names[1], tail_at),
        "zeroconf": observation(seen, names[2], names[3], tail_at),
        "second_query_ms": nullable_ms(waiter_at),
        "distinct_querier_udp_verified": Json(
          mode == "two_queriers" &&
          waiter_qm_observed &&
          primary_head_observed &&
          primary_tail_observed,
        ),
        "second_querier_received": if mode == "two_queriers" {
          Json::object({
            "avahi": observation(waiter_seen, names[0], names[1], tail_at),
            "zeroconf": observation(waiter_seen, names[2], names[3], tail_at),
          })
        } else {
          Json::null()
        },
      }),
    )
  }
  let report = Json::object({
    "baseline_both_responders": Json(baseline),
    "arms": Json::array(arms),
    "scope": Json(
      "same Linux runner; two responder implementations; two querier source IPv4 addresses on the same interface",
    ),
  })
  println(report.stringify())
  guard baseline else {
    fail("plain query did not observe all four independent registrations")
  }
}

///|
fn record_answers(
  packet : @native.Datagram,
  received_at : Int64,
  service : @model.DnsName,
  names : Array[@model.DnsName],
  seen : Map[Bytes, Int64],
) -> Unit {
  guard packet.source_port == 5353 && packet.destination_ipv4 == 0xe00000fbU else {
    return
  }
  let message = @wire.decode(packet.bytes) catch { _ => return }
  guard (message.flags & 0xf80f) == 0x8000 else { return }
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
