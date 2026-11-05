///|
/// A deliberately lossy shareable summary. Retains only fixed event tags,
/// completion and counts. Drops names, scope, endpoints, TXT, packet hex,
/// diagnostics and arbitrary JSON fields. This is not a replay trace or proof
/// of anonymity: sequence and aggregate size can still reveal activity.
pub fn redacted_output(event : Json) -> Json {
  let tag = match event {
    { "event": String(kind), .. } =>
      if [
          "configured", "subscribed", "resolving", "seen", "resolved", "updated",
          "unavailable", "removed", "diagnostic", "resolve_timeout", "outbound",
        ].contains(kind) {
        kind
      } else {
        "unknown"
      }
    _ => "unknown"
  }
  let result : Map[String, Json] = {
    "event": Json(tag),
    "redacted": Json(true),
  }
  if event
    is {
      "service": {
        "complete": True,
        "addresses": Array(addresses),
        "srv_candidates": Array(candidates),
        ..
      },
      ..
    } {
    result["complete"] = Json(true)
    result["address_count"] = Json(addresses.length())
    result["srv_candidate_count"] = Json(candidates.length())
  } else if event is { "service": { "complete": False, .. }, .. } {
    result["complete"] = Json(false)
  }
  Json::object(result)
}
