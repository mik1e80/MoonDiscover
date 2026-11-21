///|
fn link_fixture() -> (
  @model.DnsName,
  Array[@model.DnsName],
  Array[Bytes],
  Array[Bytes],
) raise {
  let service = @model.DnsName::parse("_md-tcproof._tcp.local.")
  let names = ["zc-known", "zc-unknown", "unused-a", "unused-b", "unused-c"].map(label => {
      @model.DnsName::parse(label + "." + service.to_presentation())
    },
  )
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
  let (head, first) = tc_burst(service, [answer(2)])
  let (_, second) = tc_burst(service, [answer(0), answer(3)])
  let (_, tail) = tc_burst(service, [answer(4)])
  let competitors = [@wire.qm_query(service, 12)]
  // A fixture-only, unpublished PTR makes the other queries distinct without
  // claiming either of the responder's two published PTRs.
  for i in 0U..<5U {
    competitors.push(
      @wire.query_with_answers(service, 12, [{ ..answer(2), ttl: 4500U - i, }]),
    )
  }
  (service, names, [head, with_tc(first), with_tc(second), tail], competitors)
}

///|
fn link_schedule(
  burst : Array[Bytes],
  competitors : Array[Bytes],
  competing_sources : Int32,
) -> Array[(Int32, Int32, Bytes, Int64)] {
  if competing_sources > 0 {
    let scheduled = [(0, 0, burst[0], 0L)]
    for i in 0..<competing_sources {
      scheduled.push((i + 4, i + 1, competitors[i], 8L + 6L * i.to_int64()))
    }
    let first_continuation = 10L + 6L * competing_sources.to_int64()
    scheduled.push((1, 0, burst[1], first_continuation))
    scheduled.push((2, 0, burst[2], first_continuation + 25L))
    scheduled.push((3, 0, burst[3], first_continuation + 50L))
    scheduled
  } else {
    burst.mapi((i, packet) => (i, 0, packet, 25L * i.to_int64()))
  }
}

///|
async fn link_send(
  interface : String,
  peer : String,
  plain : Bool,
  additional : Array[String],
) -> Unit {
  let (service, names, burst, competitors) = link_fixture()
  let peer_ip = extended_address(peer)
  let addresses = [interface]
  if !plain {
    addresses.append(additional)
  }
  let sockets : Array[@native.MulticastSocket] = []
  defer (for socket in sockets {
    socket.close()
  })
  for address in addresses {
    sockets.push(@native.MulticastSocket::open(extended_address(address)))
  }
  let timeline = if plain {
    [(0, 0, @wire.qm_query(service, 12), 0L)]
  } else {
    link_schedule(burst, competitors, additional.length())
  }
  let origin = @native.monotonic_ms()
  let sent : Array[Json] = []
  let order : Array[Int32] = []
  let seen : Array[Map[Bytes, Int64]] = addresses.map(_ => Map([]))
  let mut next = 0
  let mut tail_at : Int64? = None
  while @native.monotonic_ms() - origin < 1100L {
    if next < timeline.length() {
      let (id, source, packet, when) = timeline[next]
      if @native.monotonic_ms() - origin >= when {
        sockets[source].send(packet)
        let now = @native.monotonic_ms() - origin
        order.push(id)
        sent.push(Json(now.to_double()))
        if id == 3 {
          tail_at = Some(now)
        }
        next += 1
      }
    }
    for i, socket in sockets {
      for _ in 0..<16 {
        guard socket.receive(timeout_ms=0) is Some(packet) else { break }
        if packet.source_ipv4 == peer_ip &&
          packet.interface_index == socket.interface_index {
          record_answers(
            packet,
            @native.monotonic_ms() - origin,
            service,
            names,
            seen[i],
          )
        }
      }
    }
    @async.sleep(1)
  }
  println(
    Json::object({
      "send_order": Json(order),
      "sent_ms": Json::array(sent),
      "zeroconf": observation(seen[0], names[0], names[1], tail_at),
      "queriers": Json::array(
        seen.mapi((i, answers) => {
          Json::object({
            "source_ipv4": Json(addresses[i]),
            "zeroconf": observation(answers, names[0], names[1], tail_at),
          })
        }),
      ),
    }).stringify(),
  )
}

///|
async fn link_receive(
  interface : String,
  peer : String,
  ready : String,
  additional : Array[String],
) -> Unit {
  let (_, _, burst, competitors) = link_fixture()
  let timeline = link_schedule(burst, competitors, additional.length())
  let addresses = [peer]
  addresses.append(additional)
  let ips = addresses.map(extended_address)
  let socket = @native.MulticastSocket::open(extended_address(interface))
  defer socket.close()
  @fs.write_file(ready, "")
  let start = @native.monotonic_ms()
  let mut origin : Int64? = None
  let order : Array[Int32] = []
  let times : Array[Json] = []
  while @native.monotonic_ms() - start < 1850L {
    if socket.receive(timeout_ms=10) is Some(packet) &&
      packet.source_port == 5353 &&
      packet.destination_ipv4 == 0xe00000fbU &&
      packet.interface_index == socket.interface_index {
      for (id, source, query, _) in timeline {
        if packet.source_ipv4 == ips[source] && packet.bytes == query {
          let now = @native.monotonic_ms()
          if origin is None {
            origin = Some(now)
          }
          order.push(id)
          times.push(Json((now - origin.unwrap_or(now)).to_double()))
          break
        }
      }
    }
  }
  println(
    Json::object({
      "receive_order": Json(order),
      "received_ms": Json::array(times),
    }).stringify(),
  )
}
