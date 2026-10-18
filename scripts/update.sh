#!/usr/bin/env bash
# update.sh — point the flake at an upstream mcpp release.
#
#   ./scripts/update.sh            # latest published release
#   ./scripts/update.sh 2026.10.17.1
#
# Replaces release.json with the release's `mcpp-release.json`, verbatim. That
# asset is uploaded by upstream's release.yml after every platform's tarball,
# so its presence is what says a release is whole; the flake reads the version
# and every sha256 from it (package.nix). We never re-hash a tarball here: that
# would attest to what we happened to download, not to what upstream released.
#
# Exit codes: 0 updated or already current (or the release is not whole yet),
# 3 the requested version is older than release.json, anything else an error.
set -euo pipefail

REPO="mcpp-community/mcpp"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CURRENT="${ROOT}/release.json"

# Authenticated API calls when a token is around (CI): the anonymous rate
# limit is 60/h per IP and shared with every other job on the runner.
api() {
    if [[ -n "${GH_TOKEN:-${GITHUB_TOKEN:-}}" ]]; then
        curl -fsSL -H "Authorization: Bearer ${GH_TOKEN:-${GITHUB_TOKEN}}" "$@"
    else
        curl -fsSL "$@"
    fi
}

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
    latest_json=$(api "https://api.github.com/repos/${REPO}/releases/latest")
    VERSION=$(jq -r .tag_name <<<"$latest_json")
    [[ -n "$VERSION" && "$VERSION" != null ]] || { echo "error: cannot resolve latest release" >&2; exit 1; }
fi
VERSION="${VERSION#v}"
TAG="v${VERSION}"
echo ":: target ${TAG}"

TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

URL="https://github.com/${REPO}/releases/download/${TAG}/mcpp-release.json"
code=$(curl -sSL -o "$TMP" -w '%{http_code}' "$URL")
if [[ "$code" == 404 ]]; then
    # A release in progress: its tag exists before its manifest does. The
    # next run picks it up.
    echo ":: ${TAG} has no mcpp-release.json yet — the release is not whole; nothing to do"
    exit 0
fi
[[ "$code" == 200 ]] || { echo "error: HTTP ${code} for ${URL}" >&2; exit 1; }

[[ "$(jq -r .schema "$TMP")" == 1 ]] || { echo "error: manifest schema $(jq -r .schema "$TMP") is not 1" >&2; exit 1; }
[[ "$(jq -r .tag "$TMP")" == "$TAG" ]] || { echo "error: manifest tag $(jq -r .tag "$TMP") is not ${TAG}" >&2; exit 1; }
for want in linux/x86_64 linux/aarch64 macos/arm64; do
    sha=$(jq -r --arg p "${want%/*}" --arg a "${want#*/}" \
        '.assets[] | select(.platform == $p and .arch == $a) | .sha256' "$TMP")
    [[ "$sha" =~ ^[0-9a-f]{64}$ ]] || { echo "error: no valid ${want} asset in the manifest" >&2; exit 1; }
    echo ":: ${want}  ${sha}"
done

old=$(jq -r .version "$CURRENT")
if [[ "$old" == "$VERSION" ]]; then
    echo ":: release.json is already ${VERSION}"
    exit 0
fi
# Dot-separated numeric comparison: the newer of the two sorts last.
newest=$(printf '%s\n%s\n' "$old" "$VERSION" | sort -t. -k1,1n -k2,2n -k3,3n -k4,4n | tail -1)
if [[ "$newest" != "$VERSION" ]]; then
    echo "error: ${VERSION} is older than release.json (${old}); refusing to downgrade" >&2
    exit 3
fi

cp "$TMP" "$CURRENT"
echo ":: release.json ${old} -> ${VERSION}"
