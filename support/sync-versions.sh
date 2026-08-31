#!/usr/bin/env bash

# sync-versions.sh: pin a rubyfmt release's asset checksums into
# ./support/versions, and (unless --historical is passed) mark it as the
# 'latest' version this action will use.
#
# Usage:
#   support/sync-versions.sh v0.14.2-10
#   support/sync-versions.sh v0.14.2-9 --historical

set -eu

REPO="fables-tales/rubyfmt"
PLATFORMS=("Linux-x86_64" "Darwin-arm64" "Linux-aarch64")

SUPPORT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSIONS_FILE="${SUPPORT_DIR}/versions"
LATEST_FILE="${SUPPORT_DIR}/latest"

die() {
    echo "ERROR: ${*}" >&2
    exit 1
}

installed() {
    command -v "${1}" >/dev/null 2>&1
}

installed curl || die "'curl' is required to continue"

sha256_of() {
    if installed sha256sum; then
        sha256sum "${1}" | awk '{print $1}'
    else
        shasum -a 256 "${1}" | awk '{print $1}'
    fi
}

tag="${1:-}"
mark_latest=true
[[ "${2:-}" == "--historical" ]] && mark_latest=false

[[ -n "${tag}" ]] || die "Usage: ${0} <tag> [--historical]  (e.g. ${0} v0.14.2-10)"
[[ "${tag}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+-[0-9]+$ ]] || die "'${tag}' doesn't look like a rubyfmt release tag (expected e.g. v0.14.2-10)"

version="${tag#v}"
tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

for platform in "${PLATFORMS[@]}"; do
    asset="rubyfmt-${tag}-${platform}.tar.gz"
    url="https://github.com/${REPO}/releases/download/${tag}/${asset}"
    dest="${tmpdir}/${asset}"

    echo "Fetching ${asset}..."
    curl --fail --silent --show-error --location --output "${dest}" "${url}"

    sha256="$(sha256_of "${dest}")"

    # Drop any existing entry for this (version, platform) pair, then append.
    if [[ -f "${VERSIONS_FILE}" ]]; then
        grep -v -e "^${version} ${platform} " "${VERSIONS_FILE}" > "${tmpdir}/versions.tmp" || true
        mv "${tmpdir}/versions.tmp" "${VERSIONS_FILE}"
    fi
    echo "${version} ${platform} ${sha256}" >> "${VERSIONS_FILE}"
    echo "  ${platform}: ${sha256}"
done

if [[ "${mark_latest}" == "true" ]]; then
    echo "${version}" > "${LATEST_FILE}"
    echo "Marked ${version} as latest."
fi
