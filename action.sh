#!/usr/bin/env bash

# action.sh: download a pinned rubyfmt release and run it in --check mode.

set -eu

REPO="fables-tales/rubyfmt"

dbg() {
    echo "::debug::${*}"
}

err() {
    echo "::error::${*}"
}

die() {
    err "${*}"
    exit 1
}

installed() {
    command -v "${1}" >/dev/null 2>&1
}

output() {
    echo "${1}=${2}" >> "${GITHUB_OUTPUT}"
}

sha256_of() {
    if installed sha256sum; then
        sha256sum "${1}" | awk '{print $1}'
    else
        shasum -a 256 "${1}" | awk '{print $1}'
    fi
}

installed curl || die "Cannot run this action without curl"
installed tar || die "Cannot run this action without tar"

# Map the runner's OS/arch to one of rubyfmt's published release platforms.
# See: https://github.com/fables-tales/rubyfmt/releases
case "${RUNNER_OS}-${RUNNER_ARCH}" in
    Linux-X64)
        platform="Linux-x86_64"
        ;;
    Linux-ARM64)
        platform="Linux-aarch64"
        ;;
    macOS-ARM64)
        platform="Darwin-arm64"
        ;;
    *)
        die "Unsupported runner: ${RUNNER_OS}/${RUNNER_ARCH}. rubyfmt-action supports Linux (x86_64/aarch64) and Apple Silicon macOS runners only."
        ;;
esac

case "${GHA_RUBYFMT_HEADER_MODE}" in
    none) ;;
    opt-in) header_flag="--header-opt-in" ;;
    opt-out) header_flag="--header-opt-out" ;;
    *) die "'header-mode' must be one of 'none', 'opt-in', or 'opt-out' (got '${GHA_RUBYFMT_HEADER_MODE}')" ;;
esac

# Load the pinned (version, platform) -> sha256 table from ./support/versions.
declare -A checksums
while read -r version file_platform sha256; do
    [[ -z "${version}" || "${version}" == \#* ]] && continue
    checksums["${version} ${file_platform}"]="${sha256}"
done < "${GITHUB_ACTION_PATH}/support/versions"

version_regex='^v?[0-9]+\.[0-9]+\.[0-9]+-[0-9]+$'
requested_version="${GHA_RUBYFMT_VERSION}"

if [[ "${requested_version}" == "latest" ]]; then
    version="$(<"${GITHUB_ACTION_PATH}/support/latest")"
elif [[ "${requested_version}" =~ ${version_regex} ]]; then
    version="${requested_version#v}"
else
    die "'version' must be 'latest' or an exact X.Y.Z-N version (got '${requested_version}')"
fi

sha256="${checksums["${version} ${platform}"]:-}"
[[ -n "${sha256}" ]] || die "Unknown rubyfmt version/platform combination: ${version} / ${platform}. Run support/sync-versions.sh to pin a new version."

asset="rubyfmt-v${version}-${platform}.tar.gz"
url="https://github.com/${REPO}/releases/download/v${version}/${asset}"

workdir="${RUNNER_TEMP}/rubyfmt-action"
mkdir -p "${workdir}"
archive="${workdir}/${asset}"

echo "::group::Downloading rubyfmt v${version} (${platform})"
curl --fail --silent --show-error --location --output "${archive}" "${url}"
echo "::endgroup::"

actual_sha256="$(sha256_of "${archive}")"
[[ "${actual_sha256}" == "${sha256}" ]] \
    || die "Checksum mismatch for ${asset}: expected ${sha256}, got ${actual_sha256}"

tar --extract --gzip --file "${archive}" --directory "${workdir}"

rubyfmt_bin="$(find "${workdir}" -type f -name rubyfmt | head -n1)"
[[ -n "${rubyfmt_bin}" ]] || die "Could not locate the rubyfmt binary after extracting ${asset}"
chmod +x "${rubyfmt_bin}"

arguments=("--check")
[[ "${GHA_RUBYFMT_FAIL_FAST}" == "true" ]] && arguments+=("--fail-fast")
[[ "${GHA_RUBYFMT_INCLUDE_GITIGNORED}" == "true" ]] && arguments+=("--include-gitignored")
[[ -n "${header_flag:-}" ]] && arguments+=("${header_flag}")

diff_output="${workdir}/diff.txt"

echo "::group::Running rubyfmt --check"
set +e
# shellcheck disable=SC2086
"${rubyfmt_bin}" "${arguments[@]}" -- ${GHA_RUBYFMT_PATHS} | tee "${diff_output}"
exitcode="${PIPESTATUS[0]}"
set -e
echo "::endgroup::"

dbg "rubyfmt exited with code ${exitcode}"

if [[ "${exitcode}" -eq 0 ]]; then
    output "outcome" "success"
    exit 0
fi

output "outcome" "failure"

if [[ "${GHA_RUBYFMT_SUMMARY}" == "true" && -s "${diff_output}" && -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    {
        echo "### rubyfmt found unformatted files"
        echo
        echo '```diff'
        cat "${diff_output}"
        echo '```'
    } >> "${GITHUB_STEP_SUMMARY}"
fi

err "rubyfmt found formatting issues. Run 'rubyfmt -i ${GHA_RUBYFMT_PATHS}' locally to fix them."
exit "${exitcode}"
