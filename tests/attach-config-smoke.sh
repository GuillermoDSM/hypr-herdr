#!/bin/bash

set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

cp "$repo_dir/AttachConfig.js" "$repo_dir/tests/AttachConfigSmoke.qml" "$tmp_dir/"
output=$(timeout 10s quickshell --no-color -p "$tmp_dir/AttachConfigSmoke.qml" 2>&1)
printf '%s\n' "$output"
[[ $output == *ATTACH_CONFIG_OK* ]]