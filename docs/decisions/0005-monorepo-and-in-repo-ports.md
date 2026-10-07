# ADR-0005: Monorepo layout, in-repo ports of shared libraries, later swap to published packages

- **Status:** Accepted
- **Date:** 2026-10-06
- **Design:** §3.1, §9

## Context

Every official runner depends on shared Cucumber libraries:

- tag-expressions
- ci-environment
- query
- html-formatter
- junit-xml-formatter
- pretty-formatter
- compatibility-kit

None of these exists in Dart yet. The cucumber-expressions Dart port exists only on a fork branch. pub.dev rejects
packages that have path dependencies. Publishing ports under the names the Cucumber organisation will use would
squat those names.

## Decision

- **A pub workspace** with Dart SDK `^3.8.0`.
- **The runner is split into two packages:**
  - `cucumber_core`: runner-agnostic and pure Dart.
  - `cucumber`: the `package:test` host, which re-exports the core API.
- **Each ported shared library is its own workspace package.**
  - It uses the name the Cucumber organisation would publish it under, for example `cucumber_query`.
  - It has `publish_to: none`.
  - It follows the upstream API and is tested against the upstream language-neutral test data.
- **Swap later.** When a port is accepted upstream and published, the workspace package is replaced by the hosted
  dependency.

## Consequences

**Benefits:**
- Fast iteration.
- Contributing a port upstream becomes a move, not a rewrite.

**Costs:**
- `cucumber` cannot be released on pub.dev until its dependencies are published. This is accepted for now.
- Ports must keep up with upstream test data.

## Alternatives considered

- **Upstream first.** Slower, because every change waits for review.
- **Inline ports in the runner.** Harder to upstream later.
- **A single large package.**
- **Inlining ports for 0.x releases**, or claiming the `cucumber` name early.
