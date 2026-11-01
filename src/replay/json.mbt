///|
pub fn snapshot_json(snapshot : @engine.ServiceSnapshot) -> Json {
  let label = @utf8.decode(snapshot.instance.labels()[0]) catch {
    _ => "<binary instance label>"
  }
  let target = match snapshot.target {
    Some(name) => Json(name.to_presentation())
    None => Json::null()
  }
  let txt = match snapshot.txt {
    Some(record) => Json(record.entries().map(@model.bytes_hex))
    None => Json::null()
  }
  let addresses = snapshot.addresses.map(bytes => {
    @model.address_text(bytes) catch {
      _ => "<invalid address>"
    }
  })
  Json::object({
    "scope": Json(snapshot.scope),
    "service_type": Json(snapshot.service_type.to_presentation()),
    "instance": Json(snapshot.instance.to_presentation()),
    "instance_label": Json(label),
    "target": target,
    "srv_candidates": Json(
      snapshot.srv_candidates.map(candidate => {
        Json::object({
          "priority": Json(candidate.priority),
          "weight": Json(candidate.weight),
          "port": Json(candidate.port),
          "target": Json(candidate.target.to_presentation()),
          "addresses": Json(
            candidate.addresses.map(bytes => {
              @model.address_text(bytes) catch {
                _ => "<invalid address>"
              }
            }),
          ),
        })
      }),
    ),
    "port": match snapshot.port {
      Some(port) => Json(port)
      None => Json::null()
    },
    "txt_entries_hex": txt,
    "addresses": Json(addresses),
    "complete": Json(snapshot.complete),
    "missing": Json(snapshot.missing),
    "remaining_ttl_ms": Json(snapshot.remaining_ttl_ms.to_double()),
  })
}

///|
pub fn event_json(event : @engine.Event) -> Json {
  let (kind, snapshot, reason) = match event {
    @engine.Seen(s) => ("seen", Some(s), None)
    @engine.Resolved(s) => ("resolved", Some(s), None)
    @engine.Updated(s, reason) => ("updated", Some(s), Some(reason))
    @engine.Unavailable(s, reason) => ("unavailable", Some(s), Some(reason))
    @engine.Removed(s, reason) => ("removed", Some(s), Some(reason))
    @engine.Diagnostic(code, detail) =>
      return Json::object({
        "event": Json("diagnostic"),
        "code": Json(code),
        "detail": Json(detail),
      })
    @engine.ResolveTimedOut(id) =>
      return Json::object({ "event": Json("resolve_timeout"), "id": Json(id) })
  }
  Json::object({
    "event": Json(kind),
    "service": match snapshot {
      Some(s) => snapshot_json(s)
      None => Json::null()
    },
    "reason": match reason {
      Some(value) => Json(value)
      None => Json::null()
    },
  })
}
