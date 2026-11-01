"""Lightweight binary contract tests, with no network required."""
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EXE = ROOT / "_build/native/debug/build/cmd/moondiscover/moondiscover.exe"


def run(*args):
    return subprocess.run([str(EXE), *args], capture_output=True, text=True, timeout=5)


def main():
    trace = ROOT / "fixtures/replay-basic.jsonl"
    a = run("replay", "--file", str(trace), "--seed", "7")
    b = run("replay", "--file", str(trace), "--seed", "7")
    assert a.returncode == b.returncode == 0, (a.stderr, b.stderr)
    events = [json.loads(line) for line in a.stdout.splitlines()]
    assert events == [json.loads(line) for line in b.stdout.splitlines()]
    resolved = [e for e in events if e["event"] == "resolved"]
    assert len(resolved) == 1 and resolved[0]["service"]["port"] == 43219
    candidates = resolved[0]["service"]["srv_candidates"]
    assert len(candidates) == 1 and candidates[0]["port"] == 43219
    assert candidates[0]["addresses"] == resolved[0]["service"]["addresses"]
    assert any(e["event"] == "unavailable" and e["reason"] == "ttl_expired" for e in events)
    assert any(e["event"] == "removed" and e["reason"] == "ttl_expired" and e["service"]["remaining_ttl_ms"] == 0 and not e["service"]["complete"] for e in events)
    bad = run("browse", "--invalid", "x")
    assert bad.returncode != 0 and json.loads(bad.stdout)["event"] == "error"
    assert run("--help").returncode == 0
    assert run("--version").stdout.strip() == "0.2.0-dev"
    config = ROOT / ".tools/config-smoke.jsonl"
    config.parent.mkdir(exist_ok=True)
    config.write_text('{"kind":"config","format":1,"seed":4294967295,"at_ms":0}\n', encoding="utf-8")
    configured = run("replay", "--file", str(config))
    assert configured.returncode == 0 and json.loads(configured.stdout)["seed"] == 4294967295
    live = ROOT / "fixtures/live-20261024.jsonl"
    replay_a = run("replay", "--file", str(live))
    replay_b = run("replay", "--file", str(live))
    assert replay_a.returncode == replay_b.returncode == 0
    assert replay_a.stdout == replay_b.stdout
    evidence = json.loads((ROOT / "docs/evidence/windows-live-20261024.json").read_text(encoding="utf-8"))
    own_events = []
    for line in replay_a.stdout.splitlines():
        event = json.loads(line)
        if event.get("service", {}).get("instance", "").startswith(evidence["demo"] + "."):
            # Compare the original 0.1.0 fields without rewriting historical
            # evidence. The new candidate contract is asserted separately above.
            projected = {k: v for k, v in event.items() if k != "at_ms"}
            projected["service"] = {k: v for k, v in projected["service"].items() if k != "srv_candidates"}
            own_events.append(projected)
    assert own_events == evidence["replay_service_events"]
    print(json.dumps({"deterministic_replay": True, "resolved_endpoint": True, "expiry_events": True, "invalid_args_exit": True, "help_version": True, "recorded_live_events_match": True}))


if __name__ == "__main__":
    main()
