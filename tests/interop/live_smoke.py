"""One short controlled end-to-end experiment using an independent publisher."""
import argparse
from datetime import datetime, timedelta, timezone
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import importlib.metadata
import json
import platform
import socket
import subprocess
import threading
import time
import uuid
from pathlib import Path

from zeroconf import IPVersion, ServiceInfo, Zeroconf
from zeroconf._dns import DNSNsec
from zeroconf._protocol.incoming import DNSIncoming

ROOT = Path(__file__).resolve().parents[2]
BUILD = ROOT / "_build/native/debug/build"


def binary(path):
    plain = BUILD / path
    suffixed = plain.with_name(plain.name + '.exe')
    return suffixed if suffixed.is_file() else plain


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--interface", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--inspect-nsec", action="store_true")
    args = parser.parse_args()
    token = "moondiscover-" + uuid.uuid4().hex[:12]
    requests = []

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            requests.append(self.path)
            if self.path != "/moondiscover-demo":
                self.send_error(404)
                return
            body = (token + "\n").encode()
            self.send_response(200)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Connection", "close")
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *unused):
            pass

    http = ThreadingHTTPServer((args.interface, 0), Handler)
    http_thread = threading.Thread(target=http.serve_forever)
    http_thread.start()
    zc = None
    registered = None
    processes = []
    timeline = []
    resolved = threading.Event()
    updated = threading.Event()
    removed = threading.Event()
    started = time.monotonic()
    cli = binary("cmd/moondiscover/moondiscover")
    trace_path = ROOT / (".tools/capture-" + token + ".jsonl")

    def info(phase):
        return ServiceInfo("_http._tcp.local.", token + "._http._tcp.local.",
                           addresses=[socket.inet_aton(args.interface)], port=http.server_port,
                           properties={b"demo": token.encode(), b"phase": phase, b"binary": b"\x00\xff"},
                           server=token + ".local.")

    try:
        zc = Zeroconf(interfaces=[args.interface], ip_version=IPVersion.V4Only)
        registered = info(b"one")
        zc.register_service(registered)
        browse = subprocess.Popen([str(cli), "browse", "--interface", args.interface,
                                   "--service", "_http._tcp.local.", "--duration-ms", "10000", "--record", str(trace_path)],
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        processes.append(browse)

        def read_events():
            for line in browse.stdout:
                event = json.loads(line)
                service = event.get("service", {})
                if service.get("instance_label") != token:
                    continue
                event["observed_ms"] = round((time.monotonic() - started) * 1000)
                timeline.append(event)
                if event["event"] == "resolved":
                    resolved.set()
                if event["event"] == "updated" and b"phase=two".hex() in service.get("txt_entries_hex", []):
                    updated.set()
                if event["event"] == "removed" and event.get("reason") == "goodbye":
                    removed.set()

        reader = threading.Thread(target=read_events)
        reader.start()
        client = subprocess.Popen([str(binary("examples/http_connect/http_connect")), args.interface, token],
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        processes.append(client)
        got_resolution = resolved.wait(3)
        registered = info(b"two")
        zc.update_service(registered)
        got_update = updated.wait(3)
        zc.unregister_service(registered)
        registered = None
        got_goodbye = removed.wait(3)
        browse.wait(timeout=13)
        reader.join(timeout=2)
        browse_stderr = browse.stderr.read()
        client_out, client_err = client.communicate(timeout=8)
        client_events = [json.loads(line) for line in client_out.splitlines() if line.startswith("{")]
        replay_a = subprocess.run([str(cli), "replay", "--file", str(trace_path)], capture_output=True, text=True, timeout=8)
        replay_b = subprocess.run([str(cli), "replay", "--file", str(trace_path)], capture_output=True, text=True, timeout=8)
        replay_events = [json.loads(line) for line in replay_a.stdout.splitlines() if line.startswith("{")]
        replay_own = [{k: v for k, v in e.items() if k != "at_ms"} for e in replay_events if e.get("service", {}).get("instance_label") == token]
        live_own = [{k: v for k, v in e.items() if k != "observed_ms"} for e in timeline]
        doctor = subprocess.run([str(cli), "doctor", "--interface", args.interface], capture_output=True, text=True, timeout=4)
        cancel = subprocess.run([str(binary("tests/native_cancel/native_cancel")), args.interface], capture_output=True, text=True, timeout=4)
        git = ["git", "-c", "safe.directory=" + ROOT.as_posix()]
        revision = subprocess.check_output([*git, "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
        report = {
            "date": datetime.now(timezone(timedelta(hours=8))).isoformat(),
            "source_commit": revision,
            "source_dirty": bool(subprocess.check_output([*git, "status", "--porcelain"], cwd=ROOT, text=True).strip()),
            "platform": platform.platform(), "python": platform.python_version(),
            "zeroconf": importlib.metadata.version("zeroconf"), "interface_ipv4": args.interface,
            "demo": token, "http_port": http.server_port,
            "cli_sha256": hashlib.sha256(cli.read_bytes()).hexdigest(),
            "timeline": timeline, "http_requests": requests, "http_client_events": client_events,
            "trace_file": str(trace_path.relative_to(ROOT)),
            "trace_sha256": hashlib.sha256(trace_path.read_bytes()).hexdigest() if trace_path.exists() else None,
            "replay_service_events": replay_own,
            "exit_codes": {"browse": browse.returncode, "http_client": client.returncode, "doctor": doctor.returncode, "cancel": cancel.returncode},
            "stderr": {"browse": browse_stderr, "http_client": client_err, "doctor": doctor.stderr, "cancel": cancel.stderr},
            "doctor": doctor.stdout, "cancel": cancel.stdout,
            "checks": {
                "independent_service_resolved": got_resolution,
                "actual_discovered_port_used_for_http": client.returncode == 0 and any(e.get("event") == "http_verified" and e.get("discovered_port") == http.server_port and e.get("body") == token for e in client_events) and "/moondiscover-demo" in requests,
                "txt_update_event": got_update,
                "goodbye_removed_event": got_goodbye,
                "all_processes_exit_zero": all(code == 0 for code in [browse.returncode, client.returncode, doctor.returncode, cancel.returncode]),
                "async_cancellation_closed_browser": cancel.returncode == 0 and json.loads(cancel.stdout).get("cancelled_run_closed") is True,
                "recorded_replay_deterministic": replay_a.returncode == replay_b.returncode == 0 and replay_events == [json.loads(line) for line in replay_b.stdout.splitlines() if line.startswith("{")],
                "live_and_replay_service_events_match": bool(live_own) and live_own == replay_own,
            },
            "limits": ["same Windows host using an independent zeroconf process", "IPv4 QM multicast adapter; unicast intentionally excluded", "no second-device or Linux live-network evidence"],
        }
        args.output.parent.mkdir(parents=True, exist_ok=True)
        if args.inspect_nsec and trace_path.exists():
            report["independent_nsec_bitmaps"] = [
                [record.ttl, *record.rdtypes]
                for line in trace_path.read_text(encoding="utf-8").splitlines()
                if (frame := json.loads(line)).get("kind") == "packet"
                for record in DNSIncoming(bytes.fromhex(frame["packet_hex"])).answers()
                if isinstance(record, DNSNsec)
            ]
        args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(report["checks"]))
        print("report:", args.output)
        return 0 if all(report["checks"].values()) else 1
    finally:
        for process in processes:
            if process.poll() is None:
                process.kill()
                process.wait()
        if zc is not None:
            if registered is not None:
                zc.unregister_service(registered)
            zc.close()
        http.shutdown()
        http.server_close()
        http_thread.join(timeout=2)


if __name__ == "__main__":
    raise SystemExit(main())
