///|
pub(all) enum CaptureFrame {
  BrowseFrame(Int64, @model.DnsName)
  ResolveFrame(Int64, @model.DnsName, Int32)
  CancelFrame(Int64, Int32)
  AdvanceFrame(Int64)
  PacketFrame(Int64, Datagram)
  CloseFrame(Int64)
}

///|
fn Browser::capture_frame(self : Browser, frame : CaptureFrame) -> Unit {
  if !self.recording {
    return
  }
  if self.captures.length() >= 256 {
    let _ = self.captures.remove(0)
    self.capture_lost += 1
  }
  self.captures.push(frame)
}

///|
pub fn Browser::poll_capture(self : Browser) -> CaptureFrame? {
  if self.captures.is_empty() {
    None
  } else {
    Some(self.captures.remove(0))
  }
}

///|
pub fn Browser::dropped_captures(self : Browser) -> Int64 {
  self.capture_lost
}

///|
pub fn Browser::capture_config(self : Browser) -> Json {
  Json::object({
    "kind": Json("config"),
    "at_ms": Json(0),
    "format": Json(1),
    "seed": Json(self.seed),
    "scope": Json(self.scope),
    "mode": Json("ipv4_qm_multicast_only"),
    "ingress_policy": Json::object({
      "require_ip_ttl_255": Json(self.ingress_policy.require_ip_ttl_255),
      "allowed_sources": Json(
        self.ingress_policy.allowed_sources.map(source => {
          "\{ipv4_text(source.network)}/\{source.prefix_length}"
        }),
      ),
    }),
  })
}

///|
fn ipv4_text(ip : UInt32) -> String {
  "\{(ip >> 24) & 255U}.\{(ip >> 16) & 255U}.\{(ip >> 8) & 255U}.\{ip & 255U}"
}

///|
pub fn Browser::capture_json(self : Browser, frame : CaptureFrame) -> Json {
  let at = match frame {
    BrowseFrame(t, _)
    | ResolveFrame(t, _, _)
    | CancelFrame(t, _)
    | AdvanceFrame(t)
    | PacketFrame(t, _)
    | CloseFrame(t) => t
  }
  let object : Map[String, Json] = {
    "at_ms": Json(at.to_double()),
    "scope": Json(self.scope),
  }
  match frame {
    BrowseFrame(_, name) => {
      object["kind"] = Json("browse")
      object["name"] = Json(name.to_presentation())
    }
    ResolveFrame(_, name, timeout) => {
      object["kind"] = Json("resolve")
      object["name"] = Json(name.to_presentation())
      object["timeout_ms"] = Json(timeout)
    }
    CancelFrame(_, id) => {
      object["kind"] = Json("cancel")
      object["id"] = Json(id)
    }
    AdvanceFrame(_) => object["kind"] = Json("advance")
    CloseFrame(_) => object["kind"] = Json("close")
    PacketFrame(_, packet) => {
      object["kind"] = Json("packet")
      object["packet_hex"] = Json(@model.bytes_hex(packet.bytes))
      object["source_ipv4"] = Json(ipv4_text(packet.source_ipv4))
      object["source_port"] = Json(packet.source_port)
      object["interface_index"] = Json(packet.interface_index)
      object["destination_ipv4"] = Json(ipv4_text(packet.destination_ipv4))
      object["ip_ttl"] = match packet.ip_ttl {
        Some(ttl) => Json(ttl)
        None => Json::null()
      }
    }
  }
  Json::object(object)
}
