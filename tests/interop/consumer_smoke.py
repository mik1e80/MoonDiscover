"""Build a separate consumer from public APIs, locally or from the registry.

Local mode uses a moon.work mapping and proves source-level consumption only.
Registry mode has no workspace mapping and requires an exact published version.
Generated source and evidence remain outside the library checkout by default.
"""

import argparse
from datetime import datetime, timezone
import ipaddress
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[2]
CORE = """///|
fn main raise {
  let engine = @dnssd.Engine::new(seed=7U)
  let service = @dnssd.DnsName::parse("_http._tcp.local.")
  let id = engine.browse(service, "consumer", 0)
  engine.advance(120)
  guard engine.poll_outbound() is Some(query) else { fail("no public query") }
  let decoded = @dnssd.decode_packet(query.bytes)
  guard decoded.questions[0].name.same_name(service) else { fail("incorrect query") }
  engine.cancel(id, 120)
  guard engine.poll_outbound() is None else { fail("cancel did not stop queries") }
  println("consumer_core_ok")
}
"""
NATIVE = """///|
fn main raise {
  let args = @env.args()
  guard args.length() == 2 else { fail("usage: consumer-native <interface-ipv4>") }
  let ip = @socket.Addr::parse(args[1] + ":0")
  guard !ip.is_ipv6() else { fail("IPv4 required") }
  let browser = @discovery.Browser::open(ip.ip())
  browser.close()
  println("consumer_native_ok")
}
"""
NSEC_CORE_CHECK = """  let engine = @dnssd.Engine::new(seed=7U)
  let instance = @dnssd.DnsName::parse("Demo._http._tcp.local.")
  let host = @dnssd.DnsName::parse("consumer.local.")
  let _ = engine.browse(service, "consumer", 0)
  let ptr : @dnssd.Record = {
    name: service, rr_type: 12, rr_class: 1, ttl: 120U, cache_flush: false,
    section: @dnssd.Section::Answer, data: @dnssd.RData::Ptr(instance),
  }
  let srv : @dnssd.Record = {
    ..ptr, name: instance, rr_type: 33, cache_flush: true,
    section: @dnssd.Section::Additional, data: @dnssd.RData::Srv(0, 0, 8080, host),
  }
  let txt : @dnssd.Record = {
    ..srv, rr_type: 16, data: @dnssd.RData::Txt(@dnssd.TxtRecord::from_entries([b"demo=yes"])),
  }
  let address : @dnssd.Record = {
    ..srv, name: host, rr_type: 1, data: @dnssd.RData::A(b"\\x7f\\x00\\x00\\x01"),
  }
  let nsec : @dnssd.Record = {
    name: host, rr_type: 47, rr_class: 1, ttl: 2U, cache_flush: true,
    section: @dnssd.Section::Additional, data: @dnssd.RData::Nsec(host, b"\\x40"),
  }
  engine.ingest_message({id: 0, flags: 0x8400, questions: [], records: [ptr, srv, txt, address, nsec]}, "consumer", 0)
  guard engine.is_negative("consumer", host, 28) else { fail("missing public NSEC evidence") }
  guard engine.snapshots()[0].complete else { fail("IPv4 service should remain complete") }
  let mut saw_ptr = false
  for now in [120L, 1999L] {
    engine.advance(now)
    while engine.poll_outbound() is Some(outbound) {
      let packet = @dnssd.decode_packet(outbound.bytes)
      guard !packet.questions.any(q => q.rr_type == 28 && q.name.same_name(host)) else {
        fail("AAAA sent before negative TTL expired")
      }
      saw_ptr = saw_ptr || packet.questions.any(q => q.rr_type == 12 && q.name.same_name(service))
    }
  }
  guard saw_ptr && engine.is_negative("consumer", host, 28) else { fail("live negative state suppressed other query types or expired early") }
  engine.advance(2000)
  guard !engine.is_negative("consumer", host, 28) else { fail("stale public NSEC evidence") }
  engine.advance(2120)
  let mut resumed = false
  while engine.poll_outbound() is Some(outbound) {
    let packet = @dnssd.decode_packet(outbound.bytes)
    resumed = resumed || packet.questions.any(q => q.rr_type == 28 && q.name.same_name(host))
  }
  guard resumed else { fail("no AAAA emitted after NSEC expiration") }
  println("nsec_aaaa_suppressed_before_2000_ms_and_resumed_by_2120_ms")
"""
SEMVER = re.compile(r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?\Z")


def write(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def source_context():
    def git(*args):
        result = subprocess.run(["git", *args], cwd=ROOT, capture_output=True,
                                text=True, encoding="utf-8", errors="replace", timeout=10)
        return result.stdout.strip() if result.returncode == 0 else None

    status = git("status", "--porcelain")
    return {"commit": git("rev-parse", "HEAD"), "dirty": None if status is None else bool(status)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=("local", "registry"), default="local")
    parser.add_argument("--version", default="0.1.0", help="Exact dependency version; registry mode requires it to exist")
    parser.add_argument("--workspace", type=Path, help="New or empty directory outside the source checkout")
    parser.add_argument("--moon-home", type=Path, default=ROOT / ".tools/moon")
    parser.add_argument("--interface", help="Optional active IPv4 interface; also run Native socket open/close")
    parser.add_argument("--output", type=Path, help="JSON evidence path (default: workspace/consumer-evidence.json)")
    parser.add_argument("--timeout-seconds", type=int, default=240)
    args = parser.parse_args()
    if not SEMVER.fullmatch(args.version):
        parser.error("--version must be an exact semantic version")
    if args.timeout_seconds < 1:
        parser.error("--timeout-seconds must be positive")
    if args.interface:
        try:
            address = ipaddress.IPv4Address(args.interface)
            if address.is_unspecified or address.is_loopback or address.is_multicast:
                raise ValueError("an active unicast IPv4 interface is required")
        except ValueError as error:
            parser.error(str(error))

    workspace = (args.workspace or Path(tempfile.mkdtemp(prefix="moondiscover-consumer-"))).resolve()
    if workspace == ROOT or ROOT in workspace.parents:
        parser.error("consumer workspace must be outside the source checkout")
    if workspace.exists() and any(workspace.iterdir()):
        parser.error("consumer workspace must be new or empty; existing files are never overwritten")
    for ancestor in workspace.parents:
        if (ancestor / "moon.work").exists():
            parser.error("consumer workspace must not inherit an ancestor moon.work")
    workspace.mkdir(parents=True, exist_ok=True)
    moon_home = args.moon_home.resolve()
    moon = moon_home / "bin" / ("moon.exe" if os.name == "nt" else "moon")
    output = (args.output or workspace / "consumer-evidence.json").resolve()
    if output == workspace / "moon.work" or output.name == "moon.mod":
        parser.error("evidence output must not overwrite a generated manifest")
    report = {
        "format": 1,
        "started_at": datetime.now(timezone.utc).isoformat(),
        "mode": args.mode,
        "version": args.version,
        "workspace": str(workspace),
        "source_context": source_context(),
        "consumption": "workspace source mapping" if args.mode == "local" else "published registry dependency",
        "registry_consumption_verified": False,
        "commands": [],
        "checks": {"core_public_api": False, "native_public_api_build": False,
                   "native_socket_open_close": None if not args.interface else False},
        "passed": False,
    }
    env = os.environ.copy()
    env["MOON_HOME"] = str(moon_home)
    env["PATH"] = str(moon_home / "bin") + os.pathsep + env.get("PATH", "")

    def run(cwd, *arguments, expected=None):
        command = [str(moon), *arguments]
        entry = {"command": command, "cwd": str(cwd)}
        report["commands"].append(entry)
        try:
            result = subprocess.run(command, cwd=cwd, env=env, capture_output=True,
                                    text=True, encoding="utf-8", errors="replace", timeout=args.timeout_seconds)
            entry.update(returncode=result.returncode, stdout=result.stdout[-20000:], stderr=result.stderr[-20000:])
        except (OSError, subprocess.TimeoutExpired) as error:
            entry["error"] = str(error)
            raise RuntimeError("consumer command could not complete") from error
        if result.returncode != 0:
            raise RuntimeError("consumer command failed with exit " + str(result.returncode))
        if expected and expected not in result.stdout.splitlines():
            raise RuntimeError("consumer command did not emit " + expected)
        return result

    try:
        consumer = workspace / "consumer"
        write(consumer / "moon.mod", 'name = "mik1e80/dnssd-consumer-check"\nversion = "0.0.0"\npreferred_target = "js"\nimport {\n  "mik1e80/dnssd@' + args.version + '",\n  "moonbitlang/async@0.22.5",\n}\n')
        write(consumer / "cmd/core/moon.pkg", 'import { "mik1e80/dnssd" }\npkgtype(kind: "executable")\n')
        check_nsec = args.mode == "local" or tuple(map(int, re.split(r"[+-]", args.version, 1)[0].split("."))) >= (0, 3, 0)
        core = CORE.replace('  println("consumer_core_ok")', NSEC_CORE_CHECK + '  println("consumer_core_ok")') if check_nsec else CORE
        write(consumer / "cmd/core/main.mbt", core)
        write(consumer / "cmd/native/moon.pkg", 'import {\n  "mik1e80/dnssd/src/native" @discovery,\n  "moonbitlang/async/socket",\n  "moonbitlang/core/env",\n}\nsupported_targets = "native"\npkgtype(kind: "executable")\n')
        write(consumer / "cmd/native/main.mbt", NATIVE)
        if args.mode == "local":
            source_member = os.path.relpath(ROOT, workspace).replace(os.sep, "/")
            write(workspace / "moon.work", "members = [" + json.dumps(source_member) + ', "consumer"]\n')
            cwd, prefix = workspace, "consumer/"
        else:
            cwd, prefix = consumer, ""
        run(cwd, "--version")
        core_result = run(cwd, "run", prefix + "cmd/core", "--target", "js", expected="consumer_core_ok")
        if check_nsec and "nsec_aaaa_suppressed_before_2000_ms_and_resumed_by_2120_ms" not in core_result.stdout.splitlines():
            raise RuntimeError("consumer did not verify suppression and recovery from NSEC")
        report["checks"]["core_public_api"] = True
        report["checks"]["nsec_public_api"] = True if check_nsec else None
        run(cwd, "build", prefix + "cmd/native", "--target", "native")
        report["checks"]["native_public_api_build"] = True
        if args.interface:
            report["interface"] = args.interface
            run(cwd, "run", prefix + "cmd/native", "--target", "native", "--", args.interface,
                expected="consumer_native_ok")
            report["checks"]["native_socket_open_close"] = True
        report["registry_consumption_verified"] = args.mode == "registry"
        report["passed"] = True
    except Exception as error:
        report["error"] = str(error)
    finally:
        report["finished_at"] = datetime.now(timezone.utc).isoformat()
        write(output, json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"passed": report["passed"], "mode": args.mode, "evidence": str(output), "checks": report["checks"]}))
    if not report["passed"]:
        print(report["error"], file=sys.stderr)
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
