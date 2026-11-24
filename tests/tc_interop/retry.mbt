///|
async fn link_multi_retry(
  addresses : Array[String],
  window_ms~ : Int64 = 7800L,
) -> Unit {
  let ips = addresses.map(extended_address)
  let monitor = @native.MulticastSocket::open(ips[0])
  defer monitor.close()
  let browsers : Array[@native.Browser] = []
  defer (for browser in browsers {
    browser.close()
  })
  for i, ip in ips {
    browsers.push(
      @native.Browser::open(ip, seed=Some(31U + i.reinterpret_as_uint())),
    )
  }
  let service = @model.DnsName::parse("_md-tcproof._tcp.local.")
  let presentation = service.to_presentation()
  let names = ["zc-known.", "zc-unknown."].map(prefix => prefix + presentation)
  let queries : Array[Array[Int64]] = ips.map(_ => [])
  let resolved : Array[Int64?] = ips.map(_ => None)
  let start = @native.monotonic_ms()
  for browser in browsers {
    let _ = browser.browse(service)
  }
  while @native.monotonic_ms() - start < window_ms {
    for browser in browsers {
      let _ = browser.poll(timeout_ms=0)
    }
    for _ in 0..<128 {
      guard monitor.receive(timeout_ms=0) is Some(packet) else { break }
      guard packet.source_port == 5353 && packet.destination_ipv4 == 0xe00000fbU else {
        continue
      }
      let dns = @probe.independent_packet(packet.bytes) catch { _ => continue }
      if dns.flags == 0 &&
        dns.questions.any(q => q.name == presentation && q.rr_type == 12) {
        for i, ip in ips {
          if packet.source_ipv4 == ip {
            queries[i].push(@native.monotonic_ms() - start)
            break
          }
        }
      }
    }
    for i, browser in browsers {
      if resolved[i] is None {
        let snapshots = browser.snapshots()
        if names.all(name => {
            snapshots.any(s => {
              s.complete && s.instance.to_presentation() == name
            })
          }) {
          resolved[i] = Some(@native.monotonic_ms() - start)
        }
      }
    }
    if resolved.all(t => t is Some(_)) {
      break
    }
    @async.sleep(5)
  }
  println(
    Json::object({
      "origin_ms": Json(start.to_double()),
      "queriers": Json::array(
        addresses.mapi((i, address) => {
          Json::object({
            "source": Json(address),
            "qm_ms": Json(queries[i]),
            "resolved_ms": nullable_ms(resolved[i]),
          })
        }),
      ),
    }).stringify(),
  )
}

///|
async fn link_retry_peer(
  address : String,
  ready : String,
  done : String,
  sources : Array[String],
  window_ms~ : Int64 = 9500L,
) -> Unit {
  let ips = sources.map(extended_address)
  let socket = @native.MulticastSocket::open(extended_address(address))
  defer socket.close()
  let service = "_md-tcproof._tcp.local."
  let qm : Array[Array[Int64]] = ips.map(_ => [])
  let start = @native.monotonic_ms()
  let mut total = 0
  @fs.write_file(ready, "")
  while @native.monotonic_ms() - start < window_ms {
    if socket.receive(timeout_ms=10) is Some(packet) &&
      packet.interface_index == socket.interface_index &&
      packet.source_port == 5353 &&
      packet.destination_ipv4 == 0xe00000fbU {
      let dns = @probe.independent_packet(packet.bytes) catch { _ => continue }
      if (dns.flags & 0x8000) == 0 {
        for i, ip in ips {
          if packet.source_ipv4 == ip {
            total += 1
            if dns.flags == 0 &&
              dns.questions.any(q => q.name == service && q.rr_type == 12) {
              qm[i].push(@native.monotonic_ms() - start)
            }
            break
          }
        }
      }
    } else if @fs.exists(done) {
      break
    }
  }
  println(
    Json::object({
      "origin_ms": Json(start.to_double()),
      "query_packets": Json(total),
      "queriers": Json::array(
        sources.mapi((i, source) => {
          Json::object({ "source": Json(source), "qm_ms": Json(qm[i]) })
        }),
      ),
    }).stringify(),
  )
}

///|
async fn link_retry(address : String, restored : String) -> Unit {
  let ip = extended_address(address)
  let monitor = @native.MulticastSocket::open(ip)
  defer monitor.close()
  let browser = @native.Browser::open(ip, seed=Some(31U))
  defer browser.close()
  let name = @model.DnsName::parse("_md-tcproof._tcp.local.")
  let presentation = name.to_presentation()
  let start = @native.monotonic_ms()
  let _ = browser.browse(name)
  let queries : Array[Int64] = []
  let mut restored_at : Int64? = None
  while @native.monotonic_ms() - start < 6500L {
    if restored_at is None && @fs.exists(restored) {
      restored_at = Some(@native.monotonic_ms() - start)
    }
    let _ = browser.poll(timeout_ms=0)
    for _ in 0..<32 {
      guard monitor.receive(timeout_ms=0) is Some(packet) else { break }
      if packet.source_ipv4 != ip ||
        packet.source_port != 5353 ||
        packet.destination_ipv4 != 0xe00000fbU {
        continue
      }
      let dns = @probe.independent_packet(packet.bytes) catch { _ => continue }
      if dns.flags == 0 &&
        dns.questions.any(q => q.name == presentation && q.rr_type == 12) {
        queries.push(@native.monotonic_ms() - start)
      }
    }
    let snapshots = browser.snapshots()
    if !snapshots.is_empty() && restored_at is None {
      fail(
        "Browser discovered an instance before response delivery was restored",
      )
    }
    if snapshots.length() == 2 && snapshots.all(s => s.complete) {
      let instances = snapshots.map(s => s.instance.to_presentation())
      guard instances.contains("zc-known." + presentation) &&
        instances.contains("zc-unknown." + presentation) &&
        restored_at is Some(restored_ms) &&
        queries.length() >= 3 &&
        queries[1] < restored_ms &&
        queries[2] >= restored_ms else {
        fail(
          "missing query retry or unexpected resolved instances: \{Repr(queries)}",
        )
      }
      println(
        Json::object({
          "qm_ms": Json(queries),
          "restore_observed_ms": Json(restored_ms),
          "resolved_ms": Json(@native.monotonic_ms() - start),
          "instances": Json(instances),
        }).stringify(),
      )
      return
    }
    @async.sleep(5)
  }
  fail(
    "Browser did not resolve both instances after response delivery was restored: \{Repr(queries)}",
  )
}
