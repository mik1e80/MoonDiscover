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
  let known_answer = observe_known_answer(ip)
  Json::object({
    "passed": Json(true),
    "publisher": Json("Avahi independent service processes"),
    "subtype_nonmember_excluded": Json(true),
    "base_services": Json(2),
    "printer_seen": Json(1),
    "printer_resolved": Json(1),
    "shared_identity": Json(true),
    "subscription_cancellation": Json(true),
    "known_answer_observation": known_answer,
  })
}

///|
async fn observe_known_answer(ip : UInt32) -> Json {
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
  // Establish a plain-query baseline. Allow a quiet period before the
  // second arm so recent multicast responses do not explain missing data.
  let arms : Array[Json] = []
  let mut known_seen = false
  let mut control_complete = false
  let mut comparable = true
  let mut split_comparable = false
  let mut split_omitted = false
  for mode in ["plain", "single", "continuation"] {
    if mode != "plain" {
      @async.sleep(2000)
      // Drain announcements captured during the quiet period.
      for _ in 0..<64 {
        if socket.receive(timeout_ms=0) is None {
          break
        }
      }
    }
    let started = @native.monotonic_ms()
    if mode == "continuation" {
      let (head, tail) = known_answer_continuation(service, answer)
      socket.send(head)
      socket.send(tail)
    } else {
      socket.send(
        @wire.query_with_answers(
          service,
          12,
          if mode == "single" {
            [answer]
          } else {
            []
          },
        ),
      )
    }
    let deadline = started + 1300L
    let mut saw_printer = false
    let mut saw_scanner = false
    let mut first_ptr_at : Int64? = None
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
            if (
                target.same_name(printer) || target.to_presentation() == scanner
              ) &&
              first_ptr_at is None {
              first_ptr_at = Some(@native.monotonic_ms() - started)
            }
          }
        }
      }
    }
    arms.push(
      Json::object({
        "mode": Json(mode),
        "printer_seen": Json(saw_printer),
        "scanner_seen": Json(saw_scanner),
        "first_matching_ptr_ms": match first_ptr_at {
          Some(time) => Json(time.to_double())
          None => Json::null()
        },
      }),
    )
    if mode == "single" {
      known_seen = saw_printer
      comparable = control_complete && saw_scanner
    } else if mode == "continuation" {
      split_comparable = control_complete && saw_scanner
      split_omitted = !saw_printer
    } else {
      control_complete = saw_printer && saw_scanner
    }
  }
  Json::object({
    "comparable": Json(comparable),
    "known_ptr_omitted": if comparable {
      Json(!known_seen)
    } else {
      Json::null()
    },
    "arms": Json::array(arms),
    "continuation_comparable": Json(split_comparable),
    "continuation_known_ptr_omitted": if split_comparable {
      Json(split_omitted)
    } else {
      Json::null()
    },
  })
}

///|
// Small deliberate TC chain, with the matching PTR only in the final packet.
fn known_answer_continuation(
  service : @model.DnsName,
  answer : @wire.Record,
) -> (Bytes, Bytes) raise {
  let head = @wire.qm_query(service, 12).to_array()
  head[2] = b'\x02'
  let question_size = head.length()
  let complete = @wire.query_with_answers(service, 12, [answer])
  let tail = Array::make(12, b'\x00')
  tail[7] = b'\x01'
  for i in question_size..<complete.length() {
    tail.push(complete[i])
  }
  let first = Bytes::makei(head.length(), i => head[i])
  let last = Bytes::makei(tail.length(), i => tail[i])
  let first_check = @probe.independent_packet(first)
  let last_check = @probe.independent_packet(last)
  guard first_check.flags == 0x0200 &&
    first_check.questions.length() == 1 &&
    first_check.answers.is_empty() &&
    last_check.flags == 0 &&
    last_check.questions.is_empty() &&
    last_check.answers.length() == 1 else {
    fail("wrong known answer continuation fixture")
  }
  (first, last)
}
