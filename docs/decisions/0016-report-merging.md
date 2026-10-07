# ADR-0016: Per-isolate report parts with automatic merge and a merge CLI

- **Status:** Accepted
- **Date:** 2026-10-06
- **Design:** §8.4

## Context

`dart test` runs each test file in its own isolate. Files run in parallel, but the tests inside one file run one
after another. Splitting features across several entry files therefore gives parallelism, but also produces several
message streams.

Users expect a single HTML report and a single NDJSON file. CI shards running on different machines need to merge
too.

## Decision

1. **Parts.** Each suite writes its own NDJSON part to `<outputDir>/.cucumber/parts/<runId>/<suiteId>.ndjson`.
   - `runId` is `CUCUMBER_RUN_ID` if set.
   - Otherwise it is the process id, which all isolates started by one `dart test` invocation share.
2. **Automatic merge.** In `tearDownAll`, the suite:
   1. takes an exclusive lock on `<outputDir>/.cucumber/merge.lock`;
   2. merges every part of the same `runId`;
   3. rewrites the configured merged outputs;
   4. releases the lock.

   The last isolate to finish leaves the complete report.
3. **CLI.** `dart run cucumber:merge` merges parts collected from multiple machines.
4. **Merge rules:**
   - One `meta`.
   - Static messages are de-duplicated by ID (ADR-0018).
   - One synthetic `testRunStarted` (minimum timestamp) and one `testRunFinished` (maximum timestamp).
     `success` is true only if every part finished and succeeded.
   - `testRunStartedId` references are remapped.
   - `workerId` is set to the suite id, mirroring cucumber-js's parallel workers.
5. **Cleanup.** Parts from older runs are pruned.

## Consequences

- Users get one report with no extra command.
- File locking and part cleanup must be robust on Windows, macOS and Linux.
- `flutter test` runs each file in its own process, so it needs `CUCUMBER_RUN_ID` (revisit in M7).
