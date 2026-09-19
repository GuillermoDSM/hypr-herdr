#!/bin/bash

set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
session="hypr-herdr-us504-$$"
tmp_dir=$(mktemp -d)
server_pid=""
trap 'if [[ -n "$server_pid" ]]; then kill "$server_pid" 2>/dev/null || true; fi; herdr session stop "$session" >/dev/null 2>&1 || true; herdr session delete "$session" >/dev/null 2>&1 || true; rm -rf "$tmp_dir"' EXIT

herdr --session "$session" server > "$tmp_dir/herdr.log" 2>&1 &
server_pid=$!

for attempt in $(seq 1 50); do
  if herdr --session "$session" status >/dev/null 2>&1; then break; fi
  sleep 0.1
done

cp "$repo_dir/HerdrClient.qml" "$repo_dir/tests/WorkspaceCreateSmoke.qml" "$tmp_dir/"
output=$(HERDR_SOCKET_PATH="$HOME/.config/herdr/sessions/$session/herdr.sock" \
  timeout 20s quickshell --no-color -p "$tmp_dir/WorkspaceCreateSmoke.qml" 2>&1)
printf '%s\n' "$output"
[[ $output == *WORKSPACE_CREATE_SMOKE_OK* ]]
