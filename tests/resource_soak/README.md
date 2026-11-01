# Bounded wall-clock resource observation

Build with the repository's fixed toolchain, then run the Native release binary:

```text
moon build tests/resource_soak --target native --release --frozen
_build/native/release/build/tests/resource_soak/resource_soak 600
```

The fixed toolchain emits an `.exe` suffix on both Windows and Linux; use the artifact path printed by the build. Duration is 1..3600 actual wall-clock seconds; CI uses two seconds, and a separate recorded observation can use 600 seconds.

After 20 warmup cycles, each cycle creates an Engine, resolves 50 synthetic services sharing one host, repeats the input five times, updates TXT, intentionally overflows a small event queue and checks snapshot resynchronization, expires all records, closes the Engine, drains events and asserts all state counts are zero. Cached records peak at 201 during TXT replacement. The test sleeps between cycles and samples current process RSS and handle/FD counts. It emits progress every 30 seconds and a final JSON result.

The test-only C stub returns scalar measurements without retaining MoonBit pointers. Final RSS growth must be below 32 MiB and handle/FD growth at most 8 over the warmed process; these are bounded observation thresholds, not library memory guarantees. Queue drops are intentional and separately reported. This workload uses decoded records and accelerated TTL within each cycle; elapsed test duration is real, but the test does not exercise live multicast or prove day-long leak freedom.
