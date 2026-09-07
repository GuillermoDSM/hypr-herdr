#!/bin/bash

set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

cp "$repo_dir/HerdrClient.qml" "$repo_dir/IdCodec.js" "$repo_dir/LeaseCodec.js" "$repo_dir/tests/Smoke.qml" "$tmp_dir/"
output=$(timeout 10s quickshell --no-color -p "$tmp_dir/Smoke.qml" 2>&1)
printf '%s\n' "$output"
[[ $output == *HERDR_SMOKE_OK* ]]
