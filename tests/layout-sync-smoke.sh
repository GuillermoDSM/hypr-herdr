#!/bin/bash

set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

cp "$repo_dir/LayoutSync.js" "$repo_dir/tests/LayoutSyncSmoke.qml" "$tmp_dir/"

output=$(timeout 10s quickshell --no-color -p "$tmp_dir/LayoutSyncSmoke.qml" 2>&1)
printf '%s\n' "$output"
[[ $output == *LAYOUT_SYNC_OK* ]]
