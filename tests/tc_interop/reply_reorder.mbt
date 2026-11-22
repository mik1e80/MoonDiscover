///|
fn reorder_fixture() -> (@model.DnsName, Array[@model.DnsName], Array[Bytes]) raise {
  let service = @model.DnsName::parse("_md-reorder._tcp.local.")
  let names = ["first.", "second.", "extra."].map(label => {
    @model.DnsName::parse(label + service.to_presentation())
  })
  fn answer(i : Int32) -> @wire.Record {
    {
      name: service,
      rr_type: 12,
      rr_class: 1,
      ttl: 120U,
      cache_flush: false,
      data: @wire.Ptr(names[i]),
      section: @wire.Answer,
    }
  }
  fn response(answers : Array[@wire.Record]) -> Bytes raise {
    let (_, packet) = tc_burst(service, answers)
    Bytes::makei(packet.length(), i => if i == 2 { b'\x84' } else { packet[i] })
  }
  (service, names, [response([answer(0), answer(2)]), response([answer(1)])])
}

///|
async fn reply_send(address : String) -> Unit {
  let (_, _, packets) = reorder_fixture()
  let socket = @native.MulticastSocket::open(extended_address(address))
  defer socket.close()
  let start = @native.monotonic_ms()
  let times : Array[Json] = []
  for i, packet in packets {
    if i == 1 {
      @async.sleep(35)
    }
    socket.send(packet)
    times.push(Json((@native.monotonic_ms() - start).to_double()))
  }
  println(
    Json::object({ "order": Json([0, 1]), "ms": Json::array(times) }).stringify(),
  )
}

///|
async fn reply_receive(address : String, peer : String, ready : String) -> Unit {
  let (service, names, packets) = reorder_fixture()
  let source = extended_address(peer)
  let socket = @native.MulticastSocket::open(extended_address(address))
  defer socket.close()
  @fs.write_file(ready, "")
  let start = @native.monotonic_ms()
  let order : Array[Int32] = []
  let times : Array[Json] = []
  let seen : Map[Bytes, Int64] = Map([])
  while @native.monotonic_ms() - start < 650L {
    if socket.receive(timeout_ms=10) is Some(packet) &&
      packet.source_ipv4 == source &&
      packet.interface_index == socket.interface_index &&
      packet.source_port == 5353 &&
      packet.destination_ipv4 == 0xe00000fbU {
      for i, fixture in packets {
        if packet.bytes == fixture {
          let now = @native.monotonic_ms() - start
          order.push(i)
          times.push(Json(now.to_double()))
          record_answers(packet, now, service, names, seen)
          break
        }
      }
    }
  }
  println(
    Json::object({
      "order": Json(order),
      "ms": Json::array(times),
      "first_ptr_ms": nullable_ms(seen.get(names[0].canonical_key())),
      "second_ptr_ms": nullable_ms(seen.get(names[1].canonical_key())),
    }).stringify(),
  )
}
