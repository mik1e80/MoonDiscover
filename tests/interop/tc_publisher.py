"""Zeroconf fixture for the two-responder multicast experiment."""

import json
import socket
import sys
import time
from pathlib import Path

from zeroconf import IPVersion, ServiceInfo, Zeroconf


def observe_tc_timers(responder, primary_ip, ready):
    """Record timer operations in the fixture process without changing their deadlines."""
    loop = responder.loop
    call_at = loop.call_at
    next_id = 0

    def traced_call_at(when, callback, *args, context=None):
        nonlocal next_id
        if (getattr(callback, "__name__", "") != "_respond_query"
                or getattr(callback, "__self__", None) not in responder.engine.protocols
                or len(args) != 5 or args[0] is not None or args[1] != primary_ip):
            return call_at(when, callback, *args, context=context)
        next_id += 1
        timer_id = next_id
        now = loop.time()
        scheduled = {
            "tc_timer": "scheduled", "id": timer_id,
            "scheduled_monotonic_ms": round(now * 1000, 3),
            "deadline_monotonic_ms": round(when * 1000, 3),
            "nominal_delay_ms": round((when - now) * 1000),
        }

        def observe_dispatch(*callback_args):
            dispatched_at = loop.time()
            callback(*callback_args)
            print(json.dumps({
                "tc_timer": "fired", "id": timer_id,
                "fired_monotonic_ms": round(dispatched_at * 1000, 3),
                "from_schedule_ms": round((dispatched_at - now) * 1000, 3),
            }), flush=True)

        handle = call_at(when, observe_dispatch, *args, context=context)
        print(json.dumps(scheduled), flush=True)
        return handle

    def install():
        loop.call_at = traced_call_at
        Path(ready).touch(exist_ok=False)

    loop.call_soon_threadsafe(install)


if __name__ == "__main__":
    ip, ready = sys.argv[1:]
    service = "_md-tcproof._tcp.local."
    with Zeroconf(interfaces=[ip], ip_version=IPVersion.V4Only) as responder:
        for label in ("zc-known", "zc-unknown"):
            responder.register_service(
                ServiceInfo(service, f"{label}.{service}",
                            addresses=[socket.inet_aton(ip)],
                            port=18423, server="zc-tcproof.local.",
                            other_ttl=4500)
            )
        observe_tc_timers(responder, ip, ready)
        time.sleep(90)
