///|
async fn write_line(text : String) -> Unit {
  @stdio.stdout.write(text + "\n")
}

///|
async fn read_trace(path : String) -> String {
  let file = @fs.open(path, mode=ReadOnly)
  defer file.close()
  guard file.size() <= 8388608L else { fail("replay file exceeds 8 MiB") }
  let bytes : Array[Byte] = []
  while file.read_some(max_len=65536) is Some(chunk) {
    // Keep the read itself bounded if the file grows after the initial stat.
    guard chunk.length() <= 8388608 - bytes.length() else {
      fail("replay file exceeds 8 MiB")
    }
    for byte in chunk {
      bytes.push(byte)
    }
  }
  @utf8.decode(Bytes::makei(bytes.length(), i => bytes[i]))
}

///|
async fn usage() -> Unit {
  write_line(
    "MoonDiscover 0.2.1-dev\n  browse --interface IPV4 --service _http._tcp.local. [--duration-ms 5000] [--record trace.jsonl] [--allow-source CIDR,CIDR] [--require-ttl 255]\n  resolve --interface IPV4 --instance 'Demo._http._tcp.local.' [--duration-ms 5000] [--record trace.jsonl] [--allow-source CIDR,CIDR] [--require-ttl 255]\n  doctor --interface IPV4\n  replay --file trace.jsonl [--seed 1]\n  redact --file trace.jsonl [--seed 1]\nRedact exports lossy event summaries, not a replay trace. Names support DNS presentation escaping. JSONL is written to stdout.",
  )
}

///|
fn options(args : Array[String]) -> Map[String, String] raise {
  let result : Map[String, String] = Map([])
  let allowed = match args[1] {
    "browse" =>
      [
        "--interface", "--service", "--duration-ms", "--record", "--allow-source",
        "--require-ttl", "--packet-rate", "--source-rate",
      ]
    "resolve" =>
      [
        "--interface", "--instance", "--duration-ms", "--record", "--allow-source",
        "--require-ttl", "--packet-rate", "--source-rate",
      ]
    "doctor" => ["--interface"]
    "replay" | "redact" => ["--file", "--seed"]
    _ => []
  }
  let mut i = 2
  while i < args.length() {
    let key = args[i]
    guard allowed.contains(key) &&
      i + 1 < args.length() &&
      !result.contains(key) else {
      fail("unknown, duplicate or incomplete option: " + key)
    }
    result[key] = args[i + 1]
    i += 2
  }
  result
}

///|
fn ingress_policy(options : Map[String, String]) -> @native.IngressPolicy raise {
  let sources : Array[@native.SourceNetwork] = []
  if options.get("--allow-source") is Some(text) {
    // Bound parsing before materializing an arbitrarily long CIDR list.
    guard text.length() <= 2048 else {
      fail("source allowlist exceeds 2048 characters")
    }
    for entry in text.split(",") {
      guard sources.length() < 64 else { fail("source network limit (64)") }
      guard entry.split_once("/") is Some((ip, prefix)) else {
        fail("source must use IPv4/prefix CIDR syntax")
      }
      let address = @socket.Addr::parse(ip.to_owned() + ":0")
      guard !address.is_ipv6() else { fail("source CIDR must be IPv4") }
      sources.push(
        @native.SourceNetwork::new(address.ip(), number(prefix.to_owned(), 32)),
      )
    }
  }
  let strict = options.get("--require-ttl") is Some(_)
  if strict {
    guard options.get("--require-ttl") == Some("255") else {
      fail("--require-ttl accepts only 255")
    }
  }
  @native.IngressPolicy::new(allowed_sources=sources, require_ip_ttl_255=strict)
}

///|
fn required(options : Map[String, String], key : String) -> String raise {
  match options.get(key) {
    Some(value) => value
    None => fail("missing option: " + key)
  }
}

///|
fn decimal(text : String, maximum : Int64) -> Int64 raise {
  guard text.length() > 0 && text.length() <= 10 else {
    fail("invalid decimal integer")
  }
  let mut value = 0L
  for c in text {
    guard c >= '0' && c <= '9' else { fail("invalid decimal integer") }
    value = value * 10L + (c.to_int() - 48).to_int64()
    guard value <= maximum else { fail("integer exceeds option limit") }
  }
  value
}

///|
fn number(text : String, maximum : Int32) -> Int32 raise {
  decimal(text, maximum.to_int64()).to_int()
}

///|
fn interface_ipv4(options : Map[String, String]) -> UInt32 raise {
  let address = @socket.Addr::parse(required(options, "--interface") + ":0")
  guard !address.is_ipv6() else {
    fail("an explicit IPv4 interface is required")
  }
  address.ip()
}

///|
async fn run_command(args : Array[String]) -> Unit {
  if args.length() < 2 || args[1] == "--help" || args[1] == "help" {
    usage()
    return
  }
  if args[1] == "--version" {
    write_line("0.2.1-dev")
    return
  }
  let options = options(args)
  match args[1] {
    "doctor" => {
      let ip = interface_ipv4(options)
      let first = @native.MulticastSocket::open(ip)
      defer first.close()
      let second = @native.MulticastSocket::open(ip)
      second.close()
      write_line(
        Json::object({
          "event": Json("doctor"),
          "interface_index": Json(first.interface_index),
          "port": Json(5353),
          "shared_bind": Json(true),
          "mode": Json("ipv4_qm_multicast_only"),
          "network_response_tested": Json(false),
        }).stringify(),
      )
    }
    "replay" | "redact" => {
      let path = required(options, "--file")
      let content = read_trace(path)
      let mut first_line : String? = None
      for line in content.split("\n") {
        let text = line.trim().to_owned()
        if text != "" {
          guard text.length() <= 32768 else {
            fail("line exceeds 32768 characters")
          }
          first_line = Some(text)
          break
        }
      }
      let replay = match options.get("--seed") {
        Some(text) =>
          @dnssd.Replay::new(
            seed=decimal(text, 4294967295L).to_int().reinterpret_as_uint(),
          )
        None =>
          if first_line is Some(line) &&
            @json.parse(line, max_nesting_depth=16, reject_duplicate_keys=true)
            is { "kind": "config", .. } {
            @dnssd.Replay::from_config(line)
          } else {
            @dnssd.Replay::new(seed=1U)
          }
      }
      let mut count = 0
      for line in content.split("\n") {
        let line = line.trim().to_owned()
        if line == "" {
          continue
        }
        count += 1
        guard count <= 10000 else { fail("replay command count exceeds 10000") }
        for event in replay.step_line(line) {
          write_line(
            (if args[1] == "redact" {
              @replay.redacted_output(event)
            } else {
              event
            }).stringify(),
          )
        }
      }
    }
    "browse" | "resolve" => {
      let duration = number(
        options.get("--duration-ms").unwrap_or("5000"),
        3600000,
      )
      guard duration > 0 else { fail("duration must be positive") }
      let record_path = options.get("--record")
      let browser = @native.Browser::open(
        interface_ipv4(options),
        record=record_path is Some(_),
        ingress_policy=ingress_policy(options),
        packet_limit=number(
          options.get("--packet-rate").unwrap_or("256"),
          65536,
        ),
        source_limit=number(options.get("--source-rate").unwrap_or("64"), 65536),
      )
      defer browser.close()
      let trace : Array[String] = []
      let mut trace_size = 0
      if record_path is Some(_) {
        let config = browser.capture_config().stringify()
        trace.push(config)
        trace_size = config.length() + 1
      }
      fn take_captures() raise {
        while browser.poll_capture() is Some(frame) {
          let line = browser.capture_json(frame).stringify()
          guard trace.length() < 10000 &&
            trace_size + line.length() + 1 <= 8388608 else {
            fail("recording exceeds 10000 frames or 8 MiB")
          }
          trace.push(line)
          trace_size += line.length() + 1
        }
      }
      if args[1] == "browse" {
        for service in required(options, "--service").split(",") {
          let _ = browser.browse(@dnssd.DnsName::parse(service.to_owned()))
        }
      } else {
        let _ = browser.resolve(
          @dnssd.DnsName::parse(required(options, "--instance")),
          timeout_ms=duration,
        )
      }
      let mut seen = 0
      let mut resolved = 0
      browser.run(
        duration,
        event => {
          match event {
            @dnssd.Event::Seen(_) => seen += 1
            @dnssd.Event::Resolved(_) => resolved += 1
            _ => ()
          }
          write_line(@dnssd.event_json(event).stringify())
        },
        on_tick=() => take_captures(),
      )
      take_captures()
      if record_path is Some(path) {
        guard browser.dropped_captures() == 0L else {
          fail(
            "capture queue overflowed; refusing to save an incomplete recording",
          )
        }
        @fs.write_file(path, trace.join("\n") + "\n")
        write_line(
          Json::object({
            "event": Json("recorded"),
            "file": Json(path),
            "frames": Json(trace.length()),
          }).stringify(),
        )
      }
      while browser.poll_event() is Some(event) {
        write_line(@dnssd.event_json(event).stringify())
      }
      write_line(
        Json::object({
          "event": Json("summary"),
          "seen_events": Json(seen),
          "resolved_events": Json(resolved),
          "duration_ms": Json(duration),
          "observation": Json(
            if seen == 0 {
              "no_service_observed_in_window"
            } else {
              "services_observed"
            },
          ),
        }).stringify(),
      )
      if args[1] == "resolve" && resolved == 0 {
        fail("instance was not resolved within the observation window")
      }
    }
    _ => fail("unknown command: " + args[1])
  }
}

///|
async fn main {
  let args = @env.args()
  let failure = try {
    run_command(args)
    None
  } catch {
    error => Some(error)
  }
  if failure is Some(error) {
    if args.length() > 1 && args[1] == "redact" {
      // Parse/file errors may embed private source fragments or file paths.
      write_line(
        Json::object({
          "event": Json("error"),
          "redacted": Json(true),
          "message": Json("redaction failed"),
        }).stringify(),
      )
      fail("redaction failed")
    }
    write_line(
      Json::object({ "event": Json("error"), "message": Json("\{error}") }).stringify(),
    )
    raise error
  }
}
