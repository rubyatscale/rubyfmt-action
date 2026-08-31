# rubyfmt-action

Run [`rubyfmt`](https://github.com/fables-tales/rubyfmt) as a GitHub Actions
PR check.

`rubyfmt-action` downloads a pinned, checksum-verified `rubyfmt` release and
runs it with `--check`, so your job fails whenever a pull request introduces
unformatted Ruby. No Ruby installation, gem, or Docker is required — the
action just needs `curl` and `tar`, which are present on GitHub-hosted
runners by default.

## Quickstart

```yaml
name: Ruby formatting

on:
  pull_request:
    branches: ["**"]

permissions:
  contents: read

jobs:
  rubyfmt:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2

      - name: Run rubyfmt
        uses: rubyatscale/rubyfmt-action@v1
```

If `rubyfmt` finds unformatted files, the job fails, the diff is printed to
the log, and (by default) added to the job summary.

## Inputs

### `paths`

*Default*: `.`

`paths` is a whitespace-separated list of files and/or directories for
`rubyfmt` to check.

```yaml
- uses: rubyatscale/rubyfmt-action@v1
  with:
    paths: |
      app/
      lib/
```

### `version`

*Default*: `latest`

The version of `rubyfmt` to use. This can be `latest` or an exact version,
e.g. `0.14.2-10` (with or without a leading `v`). Only versions that have
been pinned in [`support/versions`](support/versions) are accepted; see
[Pinning a new version](#pinning-a-new-version) below.

### `fail-fast`

*Default*: `false`

Whether `rubyfmt` should fail immediately on syntax/IO errors, instead of
warning and continuing.

### `include-gitignored`

*Default*: `false`

Whether to also check files that are excluded by `.gitignore`.

### `header-mode`

*Default*: `none`

Controls `rubyfmt`'s magic header comment behavior:

- `none`: check every input file (default)
- `opt-in`: only check files containing a `# rubyfmt: true` header
- `opt-out`: skip files containing a `# rubyfmt: false` header

### `summary`

*Default*: `true`

Whether to write a diff of any unformatted files to the job summary
(`$GITHUB_STEP_SUMMARY`).

## Outputs

### `outcome`

Either `success` or `failure`, matching whether `rubyfmt` found any
unformatted files.

## Supported runners

`rubyfmt` only publishes precompiled binaries for a subset of platforms, so
this action supports:

- `ubuntu-latest` / other Linux x86_64 runners
- Linux aarch64 runners
- `macos-latest` / other Apple Silicon (arm64) runners

Intel Mac runners and Windows runners are not supported and will fail with a
clear error.

## Pinning a new version

This action only downloads `rubyfmt` releases whose checksums have been
pinned in [`support/versions`](support/versions), to avoid trusting a
release's contents sight-unseen at CI time. To pin a new release:

```bash
support/sync-versions.sh v0.15.0
```

This downloads each platform's release asset, records its checksum in
`support/versions`, and marks the version as `latest` in
[`support/latest`](support/latest). Pass `--historical` to pin an older
release without changing what `latest` resolves to.

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for
the full licensing terms.
