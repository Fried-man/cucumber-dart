# ADR-0020: Use the hosted `cucumber_expressions` package

- **Status:** Accepted
- **Date:** 2026-10-15
- **Design:** §3.1, §9, §11
- **Supersedes:** [ADR-0006](0006-vendored-cucumber-expressions.md)

## Context

ADR-0006 vendored the cucumber-expressions Dart port into `packages/cucumber_expressions/` because it only existed on
a fork branch. The Cucumber organisation has since published it on pub.dev as
[`cucumber_expressions`](https://pub.dev/packages/cucumber_expressions) 20.1.0 (verified publisher `cucumber.io`),
built from `dart/` in [cucumber/cucumber-expressions](https://github.com/cucumber/cucumber-expressions).

ADR-0005 says a workspace port is replaced by the hosted dependency once upstream publishes it.

## Decision

- **Depend on the hosted package.** `cucumber_core` depends on `cucumber_expressions: ^20.1.0`.
- **Remove the vendored copy.** `packages/cucumber_expressions/` and its workspace entry are deleted, together with its
  copy of the upstream `testdata/` and conformance tests. Conformance of the library is upstream's responsibility.
- **No local patches.** The design §11 gaps are not patched in this repository. Each one is either worked around in
  `cucumber_core` or contributed to cucumber/cucumber-expressions and picked up through a version bump.

## Consequences

- One less package to maintain, and no back-porting.
- `cucumber_core` no longer needs a workspace port of the expressions library to be published.
- The runner is limited to the upstream API until the §11 changes land upstream, in particular:
  - `Group.start` and `Group.end` are only set on the root group, so `stepMatchArguments` offsets for nested groups
    must be computed by the runner (or wait for upstream);
  - built-in parameter types are nullable (`ParameterType<int?>` and so on);
  - an expression's parameter types are not exposed before matching.
- Upgrades follow the upstream release cadence.

## Alternatives considered

- **Keep the vendored fork** until the §11 changes are merged upstream. Rejected: it duplicates a published package
  and keeps the back-porting burden.
- **A `dependency_overrides` / git dependency on a branch with the §11 changes.** Possible as a short-term measure for
  a specific change, but not the default.
