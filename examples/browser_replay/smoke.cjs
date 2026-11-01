"use strict";

// Exercise the exact callback used by the page, without DOM or network access.
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const root = path.resolve(__dirname, "../..");
const built = process.argv[2] ? path.resolve(process.argv[2]) : path.join(root, ".tools/browser-replay/browser_replay.js");
const context = vm.createContext({ console, TextEncoder, TextDecoder });
vm.runInContext(fs.readFileSync(built, "utf8"), context, { filename: built });
assert.equal(typeof context.moonDiscoverReplay, "function");
const execute = input => JSON.parse(context.moonDiscoverReplay(input));
const fixture = fs.readFileSync(path.join(root, "fixtures/replay-basic.jsonl"), "utf8");
const first = execute(fixture);
assert.equal(first.ok, true);
assert.deepEqual(first, execute(fixture));
assert.equal(first.outputs.find(value => value.event === "resolved").service.port, 43219);
assert.equal(first.outputs.find(value => value.event === "resolved").service.srv_candidates[0].port, 43219);
assert(first.outputs.some(value => value.event === "outbound"));
const live = execute(fs.readFileSync(path.join(root, "fixtures/live-20261024.jsonl"), "utf8"));
const evidence = JSON.parse(fs.readFileSync(path.join(root, "docs/evidence/windows-live-20261024.json"), "utf8"));
assert.equal(live.ok, true);
const liveServices = live.outputs
  .filter(value => value.service?.instance_label === evidence.demo)
  .map(({ at_ms, ...value }) => {
    // Project the original schema for the frozen 0.1.0 evidence only.
    const { srv_candidates, ...service } = value.service;
    assert(Array.isArray(srv_candidates));
    return { ...value, service };
  });
assert.deepEqual(liveServices, evidence.replay_service_events);
const config = execute('{"kind":"config","format":1,"seed":4294967295,"at_ms":0}');
assert.equal(config.ok, true);
assert.equal(config.seed, 4294967295);
assert.equal(config.outputs[0].seed, 4294967295);
const invalid = execute('\n{"kind":"advance","at_ms":10}\n{"kind":"advance","at_ms":9}');
assert.equal(invalid.ok, false);
assert.equal(invalid.line, 3);
const badJson = execute('\n{');
assert.equal(badJson.ok, false);
assert.equal(badJson.line, 2);
console.log(JSON.stringify({ browser_callback: true, deterministic_replay: true, resolved_port: true, live_service_events: liveServices.length, outbound_visible: true, config_seed: true, error_line: true }));
