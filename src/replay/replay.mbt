///|
pub suberror ReplayError {
  InvalidCommand(String)
}

///|
pub struct Replay {
  engine : @engine.Engine
  priv mut now_ms : Int64
  priv seed : UInt32
  priv mut started : Bool
  priv mut configured : Bool
  priv max_frames : Int32
  priv max_input_bytes : Int32
  priv max_packet_bytes : Int32
  priv max_output_events : Int32
  priv max_output_bytes : Int32
  priv mut frames : Int32
  priv mut input_bytes : Int32
  priv mut packet_bytes : Int32
  priv mut output_events : Int32
  priv mut output_bytes : Int32
  priv mut exhausted : Bool
}

///|
/// Limits apply to the whole Replay, including repeated step_line calls. They
/// may be lowered, never raised beyond the documented hard bounds. Exhaustion
/// closes the Engine and makes this Replay unusable; partial frames are not
/// returned. Other invalid commands still consume their input/frame budget.
pub fn Replay::new(
  seed~ : UInt32 = 1U,
  max_frames~ : Int32 = 10000,
  max_input_bytes~ : Int32 = 8388608,
  max_packet_bytes~ : Int32 = 4194304,
  max_output_events~ : Int32 = 65536,
  max_output_bytes~ : Int32 = 8388608,
) -> Replay raise {
  guard max_frames > 0 &&
    max_frames <= 10000 &&
    max_input_bytes > 0 &&
    max_input_bytes <= 8388608 &&
    max_packet_bytes > 0 &&
    max_packet_bytes <= 4194304 &&
    max_output_events > 0 &&
    max_output_events <= 65536 &&
    max_output_bytes > 0 &&
    max_output_bytes <= 8388608 else {
    raise InvalidCommand("replay budget outside hard limits")
  }
  {
    engine: @engine.Engine::new(seed~),
    now_ms: 0,
    seed,
    started: false,
    configured: false,
    max_frames,
    max_input_bytes,
    max_packet_bytes,
    max_output_events,
    max_output_bytes,
    frames: 0,
    input_bytes: 0,
    packet_bytes: 0,
    output_events: 0,
    output_bytes: 0,
    exhausted: false,
  }
}

///|
fn Replay::exhaust(self : Replay, detail : String) -> Unit raise ReplayError {
  self.exhausted = true
  self.engine.close()
  while self.engine.poll_event() is Some(_) {
    ()
  }
  raise InvalidCommand("replay budget exhausted: " + detail)
}

///|
fn Replay::append_output(
  self : Replay,
  output : Array[Json],
  event : Json,
) -> Unit raise {
  let size = @utf8.encode(event.stringify()).length() + 1
  if self.output_events >= self.max_output_events ||
    size > self.max_output_bytes - self.output_bytes {
    self.exhaust("output events/UTF-8 bytes")
  }
  self.output_events += 1
  self.output_bytes += size
  output.push(event)
}

///|
fn field(object : Map[String, Json], key : String) -> Json raise ReplayError {
  match object.get(key) {
    Some(value) => value
    None => raise InvalidCommand("missing field: " + key)
  }
}

///|
fn text(object : Map[String, Json], key : String) -> String raise {
  @json.from_json(field(object, key))
}

///|
pub fn Replay::step_line(self : Replay, line : String) -> Array[Json] raise {
  guard !self.exhausted else {
    raise InvalidCommand("replay already exhausted")
  }
  guard line.length() <= 32768 else {
    raise InvalidCommand("line exceeds 32768 characters")
  }
  let input_size = @utf8.encode(line).length() + 1
  if self.frames >= self.max_frames ||
    input_size > self.max_input_bytes - self.input_bytes {
    self.exhaust("frames/input UTF-8 bytes")
  }
  self.frames += 1
  self.input_bytes += input_size
  let object : Map[String, Json] = @json.from_json(
    @json.parse(line, max_nesting_depth=16, reject_duplicate_keys=true),
  )
  let kind = text(object, "kind")
  let numeric_time : Double = @json.from_json(field(object, "at_ms"))
  guard numeric_time >= 0.0 && numeric_time <= 9007199254740991.0 else {
    raise InvalidCommand("time outside exact JSON integer range")
  }
  let at = numeric_time.to_int64()
  guard at.to_double() == numeric_time else {
    raise InvalidCommand("fractional replay time")
  }
  guard at >= self.now_ms && at <= 9223367741887480807L else {
    raise InvalidCommand("non-monotonic or overflowing time")
  }
  let output : Array[Json] = []
  match kind {
    "config" => {
      guard !self.started &&
        !self.configured &&
        at == 0L &&
        read_config_seed(object) == self.seed else {
        raise InvalidCommand(
          "config must be first, unique and match the replay seed",
        )
      }
      self.configured = true
      self.append_output(
        output,
        Json::object({
          "event": Json("configured"),
          "seed": Json(self.seed),
          "at_ms": Json(0),
        }),
      )
    }
    "browse" => {
      let id = self.engine.browse(
        @model.DnsName::parse(text(object, "name")),
        text(object, "scope"),
        at,
      )
      self.append_output(
        output,
        Json::object({
          "event": Json("subscribed"),
          "id": Json(id),
          "at_ms": Json(at.to_double()),
        }),
      )
    }
    "resolve" => {
      let timeout : Int32 = match object.get("timeout_ms") {
        Some(value) => @json.from_json(value)
        None => 5000
      }
      let id = self.engine.resolve(
        @model.DnsName::parse(text(object, "name")),
        text(object, "scope"),
        at,
        timeout_ms=timeout,
      )
      self.append_output(
        output,
        Json::object({
          "event": Json("resolving"),
          "id": Json(id),
          "at_ms": Json(at.to_double()),
        }),
      )
    }
    "packet" => {
      let scope = text(object, "scope")
      let hex = text(object, "packet_hex")
      guard hex.length() <= 18000 else {
        raise InvalidCommand("packet hex exceeds 9000 decoded bytes")
      }
      let packet = @model.bytes_from_hex(hex)
      if packet.length() > self.max_packet_bytes - self.packet_bytes {
        self.exhaust("decoded packet bytes")
      }
      self.packet_bytes += packet.length()
      self.engine.ingest(packet, scope, at) catch {
        error => {
          self.engine.advance(at)
          self.append_output(
            output,
            Json::object({
              "event": Json("diagnostic"),
              "code": Json("packet_rejected"),
              "detail": Json("\{error}"),
              "at_ms": Json(at.to_double()),
            }),
          )
        }
      }
    }
    "advance" => self.engine.advance(at)
    "cancel" => {
      let id : Int32 = @json.from_json(field(object, "id"))
      self.engine.cancel(id, at)
    }
    "close" => {
      self.engine.advance(at)
      self.engine.close()
    }
    _ => raise InvalidCommand("unknown kind: " + kind)
  }
  self.now_ms = at
  if kind != "config" {
    self.started = true
  }
  self.drain_events(output, at)
  while self.engine.poll_outbound() is Some(packet) {
    self.drain_events(output, at)
    self.append_output(
      output,
      Json::object({
        "event": Json("outbound"),
        "at_ms": Json(at.to_double()),
        "scope": Json(packet.scope),
        "rr_type": Json(packet.rr_type),
        "packet_hex": Json(@model.bytes_hex(packet.bytes)),
      }),
    )
  }
  self.drain_events(output, at)
  output
}

///|
fn Replay::drain_events(
  self : Replay,
  output : Array[Json],
  at : Int64,
) -> Unit raise {
  while self.engine.poll_event() is Some(event) {
    let json = event_json(event)
    if json is Json::Object(fields) {
      fields["at_ms"] = Json(at.to_double())
    }
    self.append_output(output, json)
  }
}

///|
fn read_config_seed(object : Map[String, Json]) -> UInt32 raise {
  let kind = text(object, "kind")
  let format : Int32 = @json.from_json(field(object, "format"))
  guard kind == "config" && format == 1 else {
    raise InvalidCommand("unsupported trace configuration/format")
  }
  let value : Double = @json.from_json(field(object, "seed"))
  guard value >= 0.0 && value <= 4294967295.0 else {
    raise InvalidCommand("seed outside UInt32 range")
  }
  let n = value.to_int64()
  guard n.to_double() == value else {
    raise InvalidCommand("fractional replay seed")
  }
  n.to_int().reinterpret_as_uint()
}

///|
pub fn Replay::from_config(line : String) -> Replay raise {
  guard line.length() <= 32768 else {
    raise InvalidCommand("config line too long")
  }
  let object : Map[String, Json] = @json.from_json(
    @json.parse(line, max_nesting_depth=16, reject_duplicate_keys=true),
  )
  Replay::new(seed=read_config_seed(object))
}
