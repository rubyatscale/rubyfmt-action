# AGENTS.md

This file provides guidance to AI coding agents when working with code in this repository.

## What this is

A composite GitHub Action that downloads a pinned, checksum-verified [`rubyfmt`](https://github.com/fables-tales/rubyfmt) release binary and runs `rubyfmt --check`. It doesn't use Ruby, gems, or Docker. It only needs `curl` and `tar` on the runner. The user-facing docs for inputs and outputs are in `README.md`.

## Architecture

- `action.yml` declares the inputs and `outputs.outcome`, and has one composite step that runs `action.sh`. Every input is passed in as a `GHA_RUBYFMT_*` env var (e.g. `fail-fast` becomes `GHA_RUBYFMT_FAIL_FAST`), never interpolated into the script with `${{ }}`. A new input needs three changes: the `inputs:` block, the `env:` mapping, and the handling in `action.sh`.
- `action.sh` does all the work, in this order:
  1. Maps `RUNNER_OS`-`RUNNER_ARCH` to a rubyfmt release platform. Only `Linux-x86_64`, `Linux-aarch64`, and `Darwin-arm64` are supported.
  2. Resolves `version` (`latest` → contents of `support/latest`).
  3. Looks up the sha256 for the (version, platform) pair in `support/versions`.
  4. Downloads the release into `$RUNNER_TEMP/rubyfmt-action`, verifies the checksum, and extracts it.
  5. Runs `rubyfmt --check -- ${GHA_RUBYFMT_PATHS}`. The variable is intentionally unquoted so it word-splits, hence the `SC2086` disable.
  6. Writes `outcome` to `$GITHUB_OUTPUT`. On failure it also appends the diff to `$GITHUB_STEP_SUMMARY` and exits with rubyfmt's exit code.
- `support/versions` is a space-separated `<version> <platform> <sha256>` table. Any version missing from it is rejected at runtime. The file is generated, so don't hand-edit it.
- `support/latest` is a single line holding the version that `latest` resolves to.
- `support/sync-versions.sh` pins a release: it downloads each platform's asset and rewrites that version's rows in `support/versions`. The platform list lives in `PLATFORMS` here and in the `case` in `action.sh`, so keep the two in sync.

### Constraints when editing `action.sh`

- **It must run on bash 3.2**, the default `/bin/bash` on macOS runners. That rules out associative arrays (`declare -A`), `mapfile`/`readarray`, `${var,,}`, and other bash 4+ features. Under `set -u`, expanding an empty array as `"${arr[@]}"` also errors on 3.2. `arguments` avoids this because it always starts with `--check`. Use `/bin/bash ./action.sh` to test locally on a Mac, which matches the macOS runner.
- Log through the `dbg`/`err`/`die` helpers, which emit GitHub workflow commands (`::debug::`, `::error::`).
- Use `sha256_of`, which falls back from `sha256sum` to `shasum -a 256` for macOS.

## Commands

The CI `lint` job runs shellcheck and actionlint. zizmor runs through a reusable workflow in `rubyatscale/shared-config`. To run all three locally:

```bash
find . -type f -name "*.sh" -print0 | xargs -0 shellcheck
actionlint -ignore 'specifying action "\$/" in invalid format'
zizmor --offline .
```

The `-ignore` is needed because actionlint doesn't understand the `uses: $/` self-repository syntax that `ci.yml` uses to test the action from the current checkout (rhysd/actionlint#711).

There is no test runner. CI tests the action end to end by running it against `test/fixtures/formatted.rb` (expects success, on Linux and macOS) and `test/fixtures/unformatted.rb` (expects failure). To run the same check locally, set the env vars a runner would provide. Use `RUNNER_OS=Linux RUNNER_ARCH=X64` on Linux.

```bash
mkdir -p /tmp/rubyfmt-run && : > /tmp/rubyfmt-run/out
RUNNER_OS=macOS RUNNER_ARCH=ARM64 RUNNER_TEMP=/tmp/rubyfmt-run \
GITHUB_ACTION_PATH="$PWD" GITHUB_OUTPUT=/tmp/rubyfmt-run/out \
GHA_RUBYFMT_PATHS=test/fixtures/unformatted.rb GHA_RUBYFMT_VERSION=latest \
GHA_RUBYFMT_FAIL_FAST=false GHA_RUBYFMT_INCLUDE_GITIGNORED=false \
GHA_RUBYFMT_HEADER_MODE=none GHA_RUBYFMT_SUMMARY=false \
/bin/bash ./action.sh; echo "exit=$?"; cat /tmp/rubyfmt-run/out
```

On the unformatted fixture this should print the diff, exit 5, and write `outcome=failure`.

To pin a new rubyfmt release, use `support/sync-versions.sh v0.15.0`. Pass `--historical` as the second argument to pin it without changing `support/latest`.

## Dependency pinning conventions

- Third-party actions are pinned to a full commit SHA with a `# vX.Y.Z` comment. Dependabot updates them monthly as one group.
- The workflows set `permissions: {}` at the top level and grant permissions per job. Checkouts use `persist-credentials: false`. zizmor enforces this, so new workflows and jobs should follow the same pattern.
- Self-hosted Renovate (`.github/renovate-config.json`, weekly) only manages `custom.regex` pins: `support/latest`, `SHELLCHECK_VERSION` in `ci.yml`, and the SHA-pinned actionlint download script URL in `ci.yml`. Renovate bumps the version but can't update checksums, so CI on those PRs fails until a person:
  - for rubyfmt, runs `support/sync-versions.sh <tag>`;
  - for shellcheck, recomputes the sha256 of `shellcheck-<version>.linux.x86_64.tar.xz` and updates `SHELLCHECK_SHA256`.

  Renovate's regexes match the exact text of these lines (e.g. `# renovate: datasource=... depName=...` directly above `SHELLCHECK_VERSION:`), so reformatting them will silently break tracking.
