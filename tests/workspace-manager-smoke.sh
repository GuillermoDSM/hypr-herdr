#!/bin/bash

set -euo pipefail

classes=("herdr-pane-bWFuYWdlci1zbW9rZTpwMQ" "herdr-pane-bWFuYWdlci1zbW9rZTpwMg")
homes=(1100000301 1100000302)
saved_workspace=$(hyprctl activeworkspace -j | jq -r '.id')
headless=""
tmp_dir=$(mktemp -d)

dispatch() {
  hyprctl dispatch "$1" >/dev/null
}

cleanup() {
  local exit_code=$?
  trap - EXIT INT TERM
  set +e
  dispatch "hl.dsp.focus({ workspace = \"$saved_workspace\" })"
  for class in "${classes[@]}"; do
    dispatch "hl.dsp.window.close({ window = \"class:$class\" })"
  done
  sleep 0.4
  [[ -n $headless ]] && hyprctl output remove "$headless" >/dev/null 2>&1
  rm -rf "$tmp_dir"
  exit "$exit_code"
}

trap cleanup EXIT INT TERM

for home in "${homes[@]}"; do
  if hyprctl -j workspaces | jq -e --argjson id "$home" '.[] | select(.id == $id)' >/dev/null; then
    printf 'preflight failed: workspace ID %s already exists\n' "$home" >&2
    exit 1
  fi
done
for class in "${classes[@]}"; do
  if hyprctl -j clients | jq -e --arg class "$class" '.[] | select(.class == $class)' >/dev/null; then
    printf 'preflight failed: stale manager test client exists\n' >&2
    exit 1
  fi
done

before_monitors=$(hyprctl -j monitors | jq -c '[.[].name]')
hyprctl output create headless >/dev/null
headless=$(hyprctl -j monitors | jq -r --argjson before "$before_monitors" '[.[].name | select(. as $name | $before | index($name) | not)][0] // empty')
[[ -n $headless ]]
dispatch "hl.dsp.focus({ monitor = \"$headless\" })"

launcher="$tmp_dir/launch-terminal"
cp "$(dirname "${BASH_SOURCE[0]}")/workspace-manager-test-launcher.sh" "$launcher"
chmod +x "$launcher"

dispatch "hl.dsp.exec_cmd(\"$launcher ${classes[0]} adopted /tmp term-smoke-1\", { workspace = \"${homes[0]} silent\", monitor = \"$headless silent\", no_initial_focus = true })"
for _ in $(seq 1 50); do
  adopted_count=$(hyprctl -j clients | jq --arg class "${classes[0]}" '[.[] | select(.class == $class)] | length')
  [[ $adopted_count -eq 1 ]] && break
  sleep 0.1
done
[[ ${adopted_count:-0} -eq 1 ]]
dispatch "hl.dsp.workspace.rename({ workspace = ${homes[0]}, name = \"herdr:bWFuYWdlci1zbW9rZS1h\" })"

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cp "$repo_dir/WorkspaceManager.qml" "$repo_dir/IdCodec.js" "$repo_dir/LeaseCodec.js" "$repo_dir/tests/WorkspaceManagerSmoke.qml" "$tmp_dir/"

output=$(HYPR_HERDR_TEST_LAUNCHER="$launcher" timeout 15s quickshell --no-color -p "$tmp_dir/WorkspaceManagerSmoke.qml" 2>&1)
printf '%s\n' "$output"
if [[ $output != *WORKSPACE_MANAGER_OK* ]]; then
  hyprctl -j clients | jq --arg prefix "herdr-pane-bWFuYWdlci1zbW9rZTpw" '.[] | select(.class | startswith($prefix)) | {address, class, workspace}'
  exit 1
fi
[[ $output == *WORKSPACE_MANAGER_MOVED* ]]
for class in "${classes[@]}"; do
  [[ $(hyprctl -j clients | jq --arg class "$class" '[.[] | select(.class == $class)] | length') -eq 0 ]]
done
printf 'WORKSPACE_MANAGER_STATE_OK\n'
