///|
fn count_events(
  browser : @native.Browser,
  seen : Map[String, Int32],
  resolved : Map[String, Int32],
) -> Unit raise {
  for event in browser.poll(timeout_ms=0) {
    match event {
      @dnssd.Event::Seen(s) => {
        let key = s.instance.to_presentation()
        seen[key] = seen.get(key).unwrap_or(0) + 1
      }
      @dnssd.Event::Resolved(s) => {
        let key = s.instance.to_presentation()
        resolved[key] = resolved.get(key).unwrap_or(0) + 1
      }
      _ => ()
    }
  }
}

///|
async fn subtype_checks(ip : UInt32) -> Json {
  let browser = @native.Browser::open(ip)
  defer browser.close()
  let seen : Map[String, Int32] = Map([])
  let resolved : Map[String, Int32] = Map([])
  let subtype = browser.browse(
    @dnssd.DnsName::parse("_printer._sub._mdprobe._tcp.local."),
  )
  let printer = "printer-probe._mdprobe._tcp.local."
  let scanner = "scanner-probe._mdprobe._tcp.local."
  let first_deadline = @native.monotonic_ms() + 6000L
  while @native.monotonic_ms() < first_deadline {
    count_events(browser, seen, resolved)
    guard !browser.snapshots().any(s => s.instance.to_presentation() == scanner) else {
      fail("subtype admitted scanner nonmember")
    }
    if browser
      .snapshots()
      .any(s => s.instance.to_presentation() == printer && s.complete) {
      break
    }
    @async.sleep(10)
  }
  guard browser.snapshots().length() == 1 &&
    browser.snapshots()[0].instance.to_presentation() == printer &&
    browser.snapshots()[0].complete else {
    fail("Avahi printer subtype not resolved")
  }
  let base = browser.browse(@dnssd.DnsName::parse("_mdprobe._tcp.local."))
  let second_deadline = @native.monotonic_ms() + 6000L
  while @native.monotonic_ms() < second_deadline {
    count_events(browser, seen, resolved)
    if browser.snapshots().length() == 2 &&
      browser.snapshots().all(s => s.complete) {
      break
    }
    @async.sleep(10)
  }
  guard browser.snapshots().length() == 2 &&
    browser.snapshots().all(s => s.complete) else {
    fail("Avahi base browse did not resolve both services")
  }
  guard seen.get(printer) == Some(1) &&
    resolved.get(printer) == Some(1) &&
    seen.get(scanner) == Some(1) &&
    resolved.get(scanner) == Some(1) else {
    fail("base/subtype subscriptions duplicated lifecycle events")
  }
  browser.cancel(base)
  guard browser.snapshots().length() == 1 &&
    browser.snapshots()[0].instance.to_presentation() == printer else {
    fail("base cancellation removed active subtype identity")
  }
  browser.cancel(subtype)
  guard browser.snapshots().is_empty() else {
    fail("subtype cancellation retained service")
  }
  @async.sleep(1100)
  known_answer_checks(ip)
  Json::object({
    "passed": Json(true),
    "publisher": Json("Avahi independent service processes"),
    "subtype_nonmember_excluded": Json(true),
    "base_services": Json(2),
    "printer_seen": Json(1),
    "printer_resolved": Json(1),
    "shared_identity": Json(true),
    "subscription_cancellation": Json(true),
    "known_answer_suppressed_one_of_two_ptrs": Json(true),
  })
}

///|
fn known_answer_checks(ip : UInt32) -> Unit raise {
  let socket = @native.MulticastSocket::open(ip)
  defer socket.close()
  let service = @model.DnsName::parse("_mdprobe._tcp.local.")
  let printer = @model.DnsName::parse("printer-probe._mdprobe._tcp.local.")
  let scanner = "scanner-probe._mdprobe._tcp.local."
  let answer : @wire.Record = {
    name: service,
    rr_type: 12,
    rr_class: 1,
    ttl: 4500U,
    cache_flush: false,
    data: @wire.Ptr(printer),
    section: @wire.Answer,
  }
  // Observe both records in a control query. Run the suppression query first
  // so Avahi's recent-send rate control cannot explain the suppressed record.
  for known in [true, false] {
    let query = @wire.query_with_answers(
      service,
      12,
      if known {
        [answer]
      } else {
        []
      },
    )
    socket.send(query)
    let deadline = @native.monotonic_ms() + 1300L
    let mut saw_printer = false
    let mut saw_scanner = false
    while @native.monotonic_ms() < deadline {
      if socket.receive(timeout_ms=25) is Some(datagram) {
        // Avahi emits compressed responses, including Additional records.
        let response = @wire.decode(datagram.bytes) catch { _ => continue }
        if (response.flags & 0x8000) == 0 {
          continue
        }
        for rr in response.records {
          if rr.section is @wire.Answer &&
            rr.name.same_name(service) &&
            rr.rr_type == 12 &&
            rr.ttl > 0 &&
            rr.data is @wire.Ptr(target) {
            if target.same_name(printer) {
              saw_printer = true
            }
            if target.to_presentation() == scanner {
              saw_scanner = true
            }
          }
        }
      }
    }
    guard saw_scanner && saw_printer != known else {
      fail(
        "Avahi PTR suppression: known=\{known} printer=\{saw_printer} scanner=\{saw_scanner}",
      )
    }
  }
}
