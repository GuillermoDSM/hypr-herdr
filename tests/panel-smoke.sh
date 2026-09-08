#!/bin/bash

set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

cp "$repo_dir/Panel.qml" "$repo_dir/HerdrClient.qml" "$repo_dir/WorkspaceLease.qml" "$repo_dir/WorkspaceManager.qml" "$repo_dir/IdCodec.js" "$repo_dir/LeaseCodec.js" "$tmp_dir/"
cp "$repo_dir/tests/PanelSmoke.qml" "$tmp_dir/"
ln -s /usr/share/omarchy/shell/Commons "$tmp_dir/Commons"
ln -s /usr/share/omarchy/shell/Ui "$tmp_dir/Ui"

output=$(timeout 10s quickshell --no-color -p "$tmp_dir/PanelSmoke.qml" 2>&1)
printf '%s\n' "$output"
[[ $output == *PANEL_SMOKE_OK* ]]
