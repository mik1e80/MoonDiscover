///|
fn extended_address(value : String) -> UInt32 raise {
  let address = @socket.Addr::parse(value + ":0")
  guard !address.is_ipv6() else { fail("IPv4 required") }
  address.ip()
}

///|
fn with_tc(packet : Bytes) -> Bytes {
  Bytes::makei(packet.length(), i => if i == 2 { b'\x02' } else { packet[i] })
}

///|
fn by_responder(
  seen : Map[Bytes, Int64],
  names : Array[@model.DnsName],
  tail_at : Int64?,
) -> Json {
  Json::object({
    "avahi": observation(seen, names[0], names[1], tail_at),
    "zeroconf": observation(seen, names[2], names[3], tail_at),
  })
}

///|
async fn extended_probe(
  first : String,
  second : String,
  third : String,
  fourth : String?,
) -> Unit {
  let a_ip = extended_address(first)
  let b_ip = extended_address(second)
  let c_ip = extended_address(third)
  guard a_ip != b_ip && a_ip != c_ip && b_ip != c_ip else {
    fail("three distinct IPv4 addresses required")
  }
  let a = @native.MulticastSocket::open(a_ip)
  defer a.close()
  let b = @native.MulticastSocket::open(b_ip)
  defer b.close()
  let c = @native.MulticastSocket::open(c_ip)
  defer c.close()
  let sockets = [a, b, c]
  let ips = [a_ip, b_ip, c_ip]
  if fourth is Some(value) {
    let ip = extended_address(value)
    guard !ips.contains(ip) else { fail("fourth IPv4 must be distinct") }
    ips.push(ip)
    sockets.push(@native.MulticastSocket::open(ip))
  }
  defer (if sockets.length() == 4 { sockets[3].close() })
  let service = @model.DnsName::parse("_md-tcproof._tcp.local.")
  let names = ["av-known", "av-unknown", "zc-known", "zc-unknown"].map(label => {
    @model.DnsName::parse(label + "." + service.to_presentation())
  })
  fn answer(index : Int32) -> @wire.Record {
    {
      name: service,
      rr_type: 12,
      rr_class: 1,
      ttl: 4500U,
      cache_flush: false,
      data: @wire.Ptr(names[index]),
      section: @wire.Answer,
    }
  }
  let (head, tail) = tc_burst(service, [answer(0), answer(2)])
  let (_, partial_one) = tc_burst(service, [answer(0)])
  let (_, partial_two) = tc_burst(service, [answer(2)])
  let tc_one = with_tc(partial_one)
  let tc_two = with_tc(partial_two)
  for continuation in [tc_one, tc_two] {
    let decoded = @probe.independent_packet(continuation)
    guard decoded.flags == 0x0200 &&
      decoded.questions.is_empty() &&
      decoded.answers.length() == 1 else {
      fail("invalid TC continuation")
    }
  }
  let plain = @wire.qm_query(service, 12)
  // Different wire contents ensure that C exercises its own query even on a
  // responder with a recent-packet duplicate filter. B and C lack both PTRs
  // listed by A. C already knows the other two PTRs.
  let c_query = @wire.query_with_answers(service, 12, [answer(1), answer(3)])
  let d_query = @wire.query_with_answers(service, 12, [answer(1)])
  let (_, finish) = tc_burst(service, [answer(1)])
  let modes = if ips.length() == 4 {
    [
      "plain", "tc_chain", "tc_chain", "tc_chain", "ordered", "drop_middle", "swap_middle",
      "early_terminal", "solo", "four_queriers", "solo", "four_queriers", "solo",
      "four_queriers",
    ]
  } else {
    [
      "plain", "tc_chain", "tc_chain", "tc_chain", "solo", "three_queriers", "solo",
      "three_queriers", "solo", "three_queriers",
    ]
  }
  let arms : Array[Json] = []
  for trial, mode in modes {
    if trial != 0 {
      @async.sleep(2100)
    }
    for socket in sockets {
      for _ in 0..<128 {
        if socket.receive(timeout_ms=0) is None {
          break
        }
      }
    }
    let timeline : Array[(UInt32, Bytes, Int64)] = match mode {
      "plain" => [(a_ip, plain, 0L)]
      "tc_chain" =>
        [(a_ip, head, 0L), (a_ip, tc_one, 150L), (a_ip, tc_two, 300L)]
      "ordered" =>
        [
          (a_ip, head, 0L),
          (a_ip, tc_one, 35L),
          (a_ip, tc_two, 70L),
          (a_ip, finish, 105L),
        ]
      "drop_middle" =>
        [(a_ip, head, 0L), (a_ip, tc_one, 35L), (a_ip, finish, 105L)]
      "swap_middle" =>
        [
          (a_ip, head, 0L),
          (a_ip, tc_two, 35L),
          (a_ip, tc_one, 70L),
          (a_ip, finish, 105L),
        ]
      "early_terminal" =>
        [
          (a_ip, head, 0L),
          (a_ip, tc_one, 35L),
          (a_ip, finish, 70L),
          (a_ip, tc_two, 105L),
        ]
      "solo" => [(a_ip, head, 0L), (a_ip, tail, 35L)]
      "four_queriers" =>
        [
          (a_ip, head, 0L),
          (b_ip, plain, 18L),
          (c_ip, c_query, 24L),
          (ips[3], d_query, 30L),
          (a_ip, tail, 37L),
        ]
      _ =>
        [
          (a_ip, head, 0L),
          (b_ip, plain, 25L),
          (c_ip, c_query, 30L),
          (a_ip, tail, 35L),
        ]
    }
    let t0 = @native.monotonic_ms()
    let emitted : Array[Json] = []
    let heard : Array[Json] = []
    let seen : Map[Bytes, Int64] = Map([])
    let b_after_tail : Map[Bytes, Int64] = Map([])
    let c_after_tail : Map[Bytes, Int64] = Map([])
    let d_after_tail : Map[Bytes, Int64] = Map([])
    let waiters = [(b, b_after_tail), (c, c_after_tail)]
    if mode == "four_queriers" {
      waiters.push((sockets[3], d_after_tail))
    }
    let competing = mode == "three_queriers" || mode == "four_queriers"
    let mut sent = 0
    let mut observed = 0
    let mut tail_at : Int64? = None
    while @native.monotonic_ms() - t0 < 1100L {
      if sent < timeline.length() {
        let (ip, bytes, when) = timeline[sent]
        if @native.monotonic_ms() - t0 >= when {
          for i, source in ips {
            if source == ip {
              sockets[i].send(bytes)
              break
            }
          }
          let emitted_at = @native.monotonic_ms() - t0
          emitted.push(Json(emitted_at.to_double()))
          if bytes == tail || bytes == finish {
            tail_at = Some(emitted_at)
          }
          sent += 1
        }
      }
      if a.receive(timeout_ms=3) is Some(packet) {
        let now = @native.monotonic_ms() - t0
        if observed < timeline.length() {
          let (expected_ip, expected_bytes, _) = timeline[observed]
          if packet.source_ipv4 == expected_ip &&
            packet.source_port == 5353 &&
            packet.destination_ipv4 == 0xe00000fbU &&
            packet.bytes == expected_bytes {
            heard.push(Json(now.to_double()))
            observed += 1
          }
        }
        record_answers(packet, now, service, names, seen)
      }
      if competing {
        for (sock, answers) in waiters {
          for _ in 0..<16 {
            guard sock.receive(timeout_ms=0) is Some(packet) else { break }
            // Drain each socket throughout the arm. Start counting at A's
            // observed tail marker in that socket, not at its poll time.
            let mut marker = false
            if packet.source_ipv4 == a_ip && packet.bytes == tail {
              marker = true
            }
            if marker {
              answers[b""] = @native.monotonic_ms() - t0
            } else if answers.contains(b"") {
              record_answers(
                packet,
                @native.monotonic_ms() - t0,
                service,
                names,
                answers,
              )
            }
          }
        }
      }
    }
    guard observed == timeline.length() else {
      fail("missing or out-of-order source-labelled experiment packet")
    }
    if mode == "plain" {
      guard seen.length() == names.length() else {
        fail("incomplete plain baseline")
      }
    }
    if competing {
      guard waiters.all(pair => pair.1.contains(b"")) else {
        fail("a competing querier did not observe A's tail")
      }
    }
    arms.push(
      Json::object({
        "mode": Json(mode),
        "trial": Json(trial + 1),
        "query_start_monotonic_ms": Json(t0.to_double()),
        "tx_ms": Json::array(emitted),
        "a_observed_query_ms": Json::array(heard),
        "a_observed_responses": by_responder(seen, names, tail_at),
        "b_after_tail": if competing {
          by_responder(b_after_tail, names, tail_at)
        } else {
          Json::null()
        },
        "c_after_tail": if competing {
          by_responder(c_after_tail, names, tail_at)
        } else {
          Json::null()
        },
        "d_after_tail": if mode == "four_queriers" {
          by_responder(d_after_tail, names, tail_at)
        } else {
          Json::null()
        },
      }),
    )
  }
  println(
    Json::object({
      "scenario": if ips.length() == 4 {
        "TC loss reorder and four-source competition"
      } else {
        "repeated TC and three-source competition"
      },
      "arms": Json::array(arms),
    }).stringify(),
  )
}
