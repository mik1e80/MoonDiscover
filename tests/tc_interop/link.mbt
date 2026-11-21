///|
fn link_fixture() -> (@model.DnsName, Array[@model.DnsName], Array[Bytes]) raise {
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
  (service, names, [head, with_tc(first), with_tc(second), tail])
}

///|
async fn link_send(interface : String, peer : String, plain : Bool) -> Unit {
  let (service, names, burst) = link_fixture()
  let peer_ip = extended_address(peer)
  let socket = @native.MulticastSocket::open(extended_address(interface))
  defer socket.close()
  let origin = @native.monotonic_ms()
  let sent : Array[Json] = []
  let queries = if plain { [@wire.qm_query(service, 12)] } else { burst }
  let order : Array[Int32] = []
  for i, query in queries {
    if i != 0 {
      @async.sleep(25)
    }
    socket.send(query)
    order.push(i)
    sent.push(Json((@native.monotonic_ms() - origin).to_double()))
  }
  let seen : Map[Bytes, Int64] = Map([])
  while @native.monotonic_ms() - origin < 1100L {
    if socket.receive(timeout_ms=10) is Some(packet) &&
      packet.source_ipv4 == peer_ip {
      record_answers(
        packet,
        @native.monotonic_ms() - origin,
        service,
        names,
        seen,
      )
    }
  }
  println(
    Json::object({
      "send_order": Json(order),
      "sent_ms": Json::array(sent),
      "zeroconf": observation(seen, names[0], names[1], None),
    }).stringify(),
  )
}

///|
async fn link_receive(
  interface : String,
  peer : String,
  ready : String,
) -> Unit {
  let (_, _, burst) = link_fixture()
  let peer_ip = extended_address(peer)
  let socket = @native.MulticastSocket::open(extended_address(interface))
  defer socket.close()
  @fs.write_file(ready, "")
  let start = @native.monotonic_ms()
  let mut origin : Int64? = None
  let order : Array[Int32] = []
  let times : Array[Json] = []
  while @native.monotonic_ms() - start < 1850L {
    if socket.receive(timeout_ms=10) is Some(packet) &&
      packet.source_ipv4 == peer_ip &&
      packet.source_port == 5353 &&
      packet.destination_ipv4 == 0xe00000fbU &&
      packet.interface_index == socket.interface_index {
      for i, query in burst {
        if packet.bytes == query {
          let now = @native.monotonic_ms()
          if origin is None {
            origin = Some(now)
          }
          order.push(i)
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
