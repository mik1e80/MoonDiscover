"""Zeroconf fixture for the two-responder multicast experiment."""

import socket
import sys
import time
from pathlib import Path

from zeroconf import IPVersion, ServiceInfo, Zeroconf


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
        Path(ready).touch(exist_ok=False)
        time.sleep(35)
