# ADR-0008: Pending and skipped signalled by exceptions and helpers

- **Status:** Accepted
- **Date:** 2026-10-06
- **Design:** §4.7, §5.3

## Context

Implementations differ in how a step marks itself pending or skipped:

| Implementation | Mechanism |
|---|---|
| cucumber-js | Return-value sentinels (`return 'pending'`) |
| cucumber-jvm | Exceptions: classes annotated `@Pending`, and test-aborted exceptions |
| cucumber-ruby | Exceptions (`pending`, `skip_this_scenario`) |

The CCK has samples for both styles: `pending` and `skipped` use return values, while `pending-exception` and
`skipped-exception` use exceptions.

## Decision

- **Exceptions:** `PendingException` and `SkippedException`.
- **Helpers:** `pending([message])` and `skip([reason])` throw them. Both return `Never`.
- **No return-value sentinels.**

## Consequences

- Idiomatic Dart, with a single mechanism.
- On the CCK `pending` and `skipped` samples, our results carry extra `message`/`exception` fields. The CCK harness
  tolerates extra fields, as cucumber-jvm's does (ADR-0019).
