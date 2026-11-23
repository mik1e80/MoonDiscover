///|
fn browser_reorder_fixture() -> (
  @model.DnsName,
  @model.DnsName,
  @model.DnsName,
  Array[Bytes],
) raise {
  let service = @model.DnsName::parse("_md-orderproof._tcp.local.")
  let instance = @model.DnsName::parse("split._md-orderproof._tcp.local.")
  let host = @model.DnsName::parse("split-orderproof.local.")
  let ptr : @wire.Record = {
    name: service,
    rr_type: 12,
    rr_class: 1,
    ttl: 120U,
    cache_flush: false,
    data: @wire.Ptr(instance),
    section: @wire.Answer,
  }
  let srv = {
    ..ptr,
    name: instance,
    rr_type: 33,
    data: @wire.Srv(0, 0, 18424, host),
  }
  let txt = {
    ..srv,
    rr_type: 16,
    data: @wire.Txt(@model.TxtRecord::from_entries([b"stage=split"])),
  }
  let addr = {
    ..srv,
    name: host,
    rr_type: 1,
    data: @wire.A(b"\xc0\x00\x02\x0a"),
  }
  let unrelated = {
    ..addr,
    name: @model.DnsName::parse("unrelated-orderproof.local."),
  }
  fn reply(records : Array[@wire.Record]) -> Bytes raise {
    let bytes = b"\x00\x00\x84\x00\x00\x00\x00\x00\x00\x00\x00\x00".to_array()
    bytes[7] = records.length().to_byte()
    for record in records {
      let query = @wire.query_with_answers(record.name, record.rr_type, [record])
      let start = 16 + record.name.to_wire().length()
      for i in start..<query.length() {
        bytes.push(query[i])
      }
    }
    Bytes::makei(bytes.length(), i => bytes[i])
  }
  // Only the PTR packet has two answers, so the egress classifier selects it.
  (service, instance, host, [reply([ptr, unrelated]), reply([srv, txt, addr])])
}

///|
async fn browser_reply_receive(
  address : String,
  peer : String,
  ready : String,
) -> Unit {
  let (service, instance, host, packets) = browser_reorder_fixture()
  let ip = extended_address(address)
  let source = extended_address(peer)
  let monitor = @native.MulticastSocket::open(ip)
  defer monitor.close()
  let browser = @native.Browser::open(ip, seed=Some(31U))
  defer browser.close()
  let _ = browser.browse(service)
  @fs.write_file(ready, "")
  let start = @native.monotonic_ms()
  let order : Array[Int32] = []
  let times : Array[Json] = []
  let mut intermediate : Json? = None
  let mut complete_at : Int64? = None
  while @native.monotonic_ms() - start < 650L {
    let _ = browser.poll(timeout_ms=0)
    for _ in 0..<16 {
      guard monitor.receive(timeout_ms=0) is Some(packet) else { break }
      guard packet.source_ipv4 == source &&
        packet.source_port == 5353 &&
        packet.interface_index == monitor.interface_index &&
        packet.destination_ipv4 == 0xe00000fbU else {
        continue
      }
      for i, fixture in packets {
        if packet.bytes == fixture {
          order.push(i)
          times.push(Json((@native.monotonic_ms() - start).to_double()))
          break
        }
      }
    }
    let snapshots = browser.snapshots()
    if order.length() == 1 &&
      browser.stats().accepted == 1L &&
      intermediate is None {
      guard snapshots.all(s => !s.complete) else {
        fail("Browser completed an instance with only one response")
      }
      intermediate = Some(
        Json::object({
          "visible_instances": Json(snapshots.length()),
          "cached_records": Json(browser.engine_stats().cached_records),
        }),
      )
    }
    if complete_at is None && snapshots.any(s => s.complete) {
      guard order.length() == 2 else { fail("incomplete arrival evidence") }
      complete_at = Some(@native.monotonic_ms() - start)
    }
    @async.sleep(2)
  }
  let snapshots = browser.snapshots()
  guard snapshots is [snapshot] &&
    snapshot.instance.same_name(instance) &&
    snapshot.target is Some(target) &&
    target.same_name(host) &&
    snapshot.port == Some(18424) &&
    snapshot.txt is Some(txt) &&
    txt.entries() == [b"stage=split"] &&
    snapshot.addresses == [b"\xc0\x00\x02\x0a"] &&
    snapshot.complete &&
    browser.stats().accepted == 2L &&
    intermediate is Some(partial) &&
    complete_at is Some(resolved) else {
    fail("Browser did not retain and combine the two responses: \{Repr(order)}")
  }
  println(
    Json::object({
      "order": Json(order),
      "ms": Json::array(times),
      "complete": Json(true),
      "intermediate": partial,
      "resolved_ms": Json(resolved.to_double()),
      "instance": Json(instance.to_presentation()),
      "target": Json(host.to_presentation()),
      "port": Json(18424),
      "txt": Json("stage=split"),
      "ipv4": Json("192.0.2.10"),
      "accepted": Json(browser.stats().accepted.to_double()),
    }).stringify(),
  )
}
