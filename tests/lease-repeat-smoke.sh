#!/bin/bash

set -euo pipefail

slot=193
home=1100000193
parking=2000791107
prefix="hypr-herdr-repeat-smoke"
classes=("$prefix-slot" "$prefix-home")
ids=($slot $home $parking)
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

  local active
  active=$(hyprctl activeworkspace -j 2>/dev/null | jq -r '.id' 2>/dev/null)
  for id in "${ids[@]}"; do
    if [[ $active == "$id" ]]; then
      dispatch "hl.dsp.focus({ workspace = \"$saved_workspace\" })"
      break
    fi
  done
  for class in "${classes[@]}"; do
    dispatch "hl.dsp.window.close({ window = \"class:$class\" })"
  done
  sleep 0.5
  [[ -n $headless ]] && hyprctl output remove "$headless" >/dev/null 2>&1

  local clients outputs
  clients=$(hyprctl -j clients 2>/dev/null | jq --arg prefix "$prefix" '[.[] | select(.class | startswith($prefix))] | length' 2>/dev/null)
  outputs=$(hyprctl -j monitors 2>/dev/null | jq --arg name "$headless" '[.[] | select(.name == $name)] | length' 2>/dev/null)
  if [[ ${clients:-1} -ne 0 || ${outputs:-1} -ne 0 ]]; then
    printf 'cleanup failed: clients=%s outputs=%s\n' "$clients" "$outputs" >&2
    exit 1
  fi
  rm -rf "$tmp_dir"
  exit "$exit_code"
}

trap cleanup EXIT INT TERM

for id in "${ids[@]}"; do
  if hyprctl -j workspaces | jq -e --argjson id "$id" '.[] | select(.id == $id)' >/dev/null; then
    printf 'preflight failed: workspace ID %s already exists\n' "$id" >&2
    exit 1
  fi
done

if hyprctl -j clients | jq -e --arg prefix "$prefix" '.[] | select(.class | startswith($prefix))' >/dev/null; then
  printf 'preflight failed: stale test clients exist\n' >&2
  exit 1
fi

before_monitors=$(hyprctl -j monitors | jq -c '[.[].name]')
hyprctl output create headless >/dev/null
headless=$(hyprctl -j monitors | jq -r --argjson before "$before_monitors" '[.[].name | select(. as $name | $before | index($name) | not)][0] // empty')
[[ -n $headless ]]

launch() {
  local class=$1
  local workspace=$2
  dispatch "hl.dsp.exec_cmd(\"foot --app-id=$class --title=$class\", { workspace = \"$workspace silent\", monitor = \"$headless silent\", no_initial_focus = true })"
}

launch "$prefix-slot" "$slot"
launch "$prefix-home" "$home"

for _ in $(seq 1 50); do
  count=$(hyprctl -j clients | jq --arg prefix "$prefix" '[.[] | select(.class | startswith($prefix))] | length')
  [[ $count -eq 2 ]] && break
  sleep 0.1
done
[[ ${count:-0} -eq 2 ]]
sleep 1

dispatch "hl.dsp.workspace.rename({ workspace = \"$home\", name = \"herdr:v1:$home:dzE\" })"
dispatch "hl.dsp.focus({ monitor = \"$headless\" })"
dispatch "hl.dsp.focus({ workspace = \"$slot\" })"

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cp "$repo_dir/WorkspaceLease.qml" "$repo_dir/IdCodec.js" "$repo_dir/LeaseCodec.js" "$repo_dir/tests/LeaseRepeatSmoke.qml" "$tmp_dir/"
output=$(timeout 10s quickshell --no-color -p "$tmp_dir/LeaseRepeatSmoke.qml" 2>&1)
printf '%s\n' "$output"
if [[ $output != *LEASE_REPEAT_OK* ]]; then
  hyprctl -j workspaces | jq '.[] | select(.id == 193 or .id == 1100000193 or .id == 2000791107) | {id, name, windows}'
  exit 1
fi

slot_state=$(hyprctl -j workspaces | jq -c --argjson id "$slot" '.[] | select(.id == $id) | {id, name, windows}')
[[ $slot_state == '{"id":193,"name":"193","windows":1}' ]]
[[ $(hyprctl -j workspaces | jq --argjson id "$home" '[.[] | select(.id == $id and .name == "herdr:v1:1100000193:dzE")] | length') -eq 1 ]]
[[ $(hyprctl -j workspaces | jq '[.[] | select(.name | startswith("hypr-herdr:v1:parked"))] | length') -eq 0 ]]
printf 'LEASE_REPEAT_STATE_OK\n'