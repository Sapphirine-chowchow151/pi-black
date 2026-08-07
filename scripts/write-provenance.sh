#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../config/pi.env
source "$repo_root/config/pi.env"

output="${1:-}"
release_tag="${2:-untagged}"
if [[ -z "$output" ]]; then
    echo "Usage: $0 <output-file> [release-tag]" >&2
    exit 2
fi

patches=("$repo_root"/patches/*.patch)
patch_sha256="$({
    for patch in "${patches[@]}"; do
        cat "$patch"
    done
} | sha256sum | awk '{print $1}')"
cat > "$output" <<EOF
distribution=$DISTRIBUTION_NAME
release_tag=$release_tag
patch_repository_commit=${GITHUB_SHA:-local}
pi_repository=$PI_REPOSITORY
pi_base_commit=$PI_BASE_COMMIT
pi_patched_commit=$PI_PATCHED_COMMIT
pi_version=$PI_VERSION
claude_code_protocol_version=$CLAUDE_CODE_PROTOCOL_VERSION
node_version=$NODE_VERSION
bun_version=$BUN_VERSION
patch_sha256=$patch_sha256
build_script=scripts/build-binaries.sh --offline-model-data
live_provider_test=false
EOF
