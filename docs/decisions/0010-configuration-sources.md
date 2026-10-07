# ADR-0010: Configuration from code, `cucumber.yaml` profiles and `CUCUMBER_*` environment

- **Status:** Accepted
- **Date:** 2026-10-06
- **Design:** §4.9

## Context

`dart test` owns the command line, so we cannot add flags such as `--tags`. CI pipelines need to override settings
without changing code. Other implementations configure themselves like this:

| Implementation | Configuration |
|---|---|
| cucumber-js, cucumber-ruby | Profiles in config files |
| cucumber-jvm | Properties, environment variables and system properties |

## Decision

- **Precedence** (later sources win):

  > built-in defaults < code (`CucumberOptions`) < `cucumber.yaml` profile(s) < `CUCUMBER_*` environment variables

- **Profiles** are selected with `CUCUMBER_PROFILE`. The `default` profile applies when it exists and no profile is
  named.
- **Environment variable names** follow cucumber-jvm's property naming, for example `CUCUMBER_FILTER_TAGS` and
  `CUCUMBER_EXECUTION_DRY_RUN`.
- **Code only:** `glue` and `world` can only be set in code.
- **Flutter devices** will read the same keys from `--dart-define`.
- *(Proposed)* merge rules:
  - scalars override;
  - `tags` are combined with `and`;
  - lists are replaced.

## Consequences

- CI can select profiles or override any setting.
- Configuration resolution has to be documented carefully, including the merge rules.
