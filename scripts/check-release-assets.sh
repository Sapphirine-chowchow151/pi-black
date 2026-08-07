#!/usr/bin/env bash
set -euo pipefail

assets_dir="${1:-}"
if [[ -z "$assets_dir" ]]; then
    echo "Usage: $0 <release-assets-directory>" >&2
    exit 2
fi

expected=(
    pi-darwin-arm64.tar.gz
    pi-darwin-x64.tar.gz
    pi-linux-arm64.tar.gz
    pi-linux-x64.tar.gz
    pi-windows-arm64.zip
    pi-windows-x64.zip
    0001-feat-ai-add-Claude-Code-OAuth-request-compatibility.patch
    PI_BUILD_INPUTS.env
    BUILD.md
    PROVENANCE.txt
    SHA256SUMS
)
for asset in "${expected[@]}"; do
    test -f "$assets_dir/$asset" || {
        echo "Missing release asset: $asset" >&2
        exit 1
    }
done

(
    cd "$assets_dir"
    sha256sum -c SHA256SUMS
)
