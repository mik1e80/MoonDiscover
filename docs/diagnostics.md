# Diagnostic and transport error codes

Status: `main` / `0.2.0-dev`, updated 2026-11-01.

`Engine` emits `Diagnostic(code, detail)` events for recoverable protocol, capacity, and scheduling conditions. JSON event output uses `event: "diagnostic"`, `code`, and `detail`. The code is the machine-readable category; the detail is for logs and may change. Consumers should handle unknown codes by logging or counting them rather than failing.

## Engine diagnostic codes

| Code | Meaning | Suggested response |
| --- | --- | --- |
| `event_overflow` | The bounded event queue discarded queued events. | Read `snapshots()` and rebuild application state; inspect `dropped_events()` if using Engine directly. |
| `query_limit` | More desired questions were created than the configured query capacity allows. | Review scope and subscription count; continue processing the questions that fit. |
| `outbound_limit` | The pending outbound-query queue is full; due queries were deferred. | Keep draining `poll_outbound()` and advancing the Engine. |
| `service_limit` | More matching instances exist than the configured service capacity allows. | Increase capacity if appropriate or narrow the subscription. |
| `unsupported_instance_domain` | A PTR target does not match the subscribed local service type. | Ignore that target; check the publisher or the subscribed type if unexpected. |
| `packet_rejected` | An inbound packet could not be decoded. Native polling continues after this diagnostic. | Record the detail for troubleshooting; no service state is admitted from that packet. |
| `query_invalid` | The question itself could not be encoded. | Check the service name and record type supplied by the caller. |
| `known_answer_limit` | Known-Answer data exceeded an encoding budget; a valid question was sent as plain QM instead. | Usually no action is needed; inspect the detail if this is frequent. |
| `outbound_batch_interrupted` | A multi-packet Known-Answer burst was interrupted before it was fully drained. | Drain and send each continuation packet before changing Engine input or time. |

`packet_rejected` is also used by Replay for malformed recorded packet bytes. Diagnostic events describe a condition; they are not all fatal and do not imply the Browser has closed.

## Native transport error codes

Native methods can raise `TransportError`. Call `TransportError::diagnostic_code()` to classify it without parsing display text.

| Code | Error | Meaning |
| --- | --- | --- |
| `transport_closed` | `BrowserClosed` | An operation used a closed Browser or socket. |
| `invalid_transport_argument` | `InvalidArgument` | An interface value, timeout, or I/O length is invalid. |
| `interface_unavailable` | `InterfaceUnavailable` | The selected interface is unavailable or its index changed. Reopen the Browser on the active interface and restore subscriptions. |
| `socket_error` | `SocketError` | A system socket operation failed; the error retains operation context and an OS code. |

Transport errors are separate from Engine diagnostic events. The transport currently does not migrate subscriptions automatically when an interface changes; see [Native lifecycle](native-lifecycle.md).

## Consumer guidance

- Branch on the diagnostic `code`, not on English `detail` text.
- Handle codes you know and retain unknown codes in logs for forward compatibility.
- After `event_overflow`, resynchronize from snapshots because earlier queued events were lost.
- Keep normal service events, recoverable diagnostics, and raised transport errors as separate application paths.

See [service and event model](model.md) for lifecycle semantics and [public Engine interface](../src/engine/pkg.generated.mbti) for the current development API.
