#!/bin/bash

set -euo pipefail

slot=91
home_a=1000000091
home_b=1000000092
parking=1000000191
test_ids=($slot 92 93 94 $home_a $home_b $parking 1000000194)
test_prefix="hypr-herdr-spike"
classes=("$test_prefix-slot" "$test_prefix-a" "$test_prefix-a2" "$test_prefix-b")
saved_workspace=$(hyprctl activeworkspace -j | jq -r '.id')
headless=""
rule_created=false

workspace_exists() {
  local id=$1
  hyprctl -j workspaces | jq -e --argjson id "$id" '.[] | select(.id == $id)' >/dev/null
}

workspace_id_by_name() {
  local name=$1
  hyprctl -j workspaces | jq -r --arg name "$name" '[.[] | select(.name == $name) | .id][0] // empty'
}

wait_for_clients() {
  local expected=$1
  for _ in $(seq 1 50); do
    local count
    count=$(hyprctl -j clients | jq --arg prefix "$test_prefix" '[.[] | select(.class | startswith($prefix))] | length')
    [[ $count -eq $expected ]] && return 0
    sleep 0.1
  done
  return 1
}

dispatch() {
  hyprctl dispatch "$1" >/dev/null
}

cleanup() {
  local exit_code=$?
  trap - EXIT INT TERM
  set +e

  if [[ $rule_created == true ]]; then
    hyprctl eval 'if hypr_herdr_spike_rule then hypr_herdr_spike_rule:set_enabled(false); hypr_herdr_spike_rule = nil end' >/dev/null 2>&1
  fi

  local active
  active=$(hyprctl activeworkspace -j 2>/dev/null | jq -r '.id' 2>/dev/null)
  for id in "${test_ids[@]}"; do
    if [[ $active == "$id" ]]; then
      dispatch "hl.dsp.focus({ workspace = \"$saved_workspace\" })"
      break
    fi
  done

  for class in "${classes[@]}"; do
    dispatch "hl.dsp.window.close({ window = \"class:$class\" })"
  done
  sleep 0.5

  if [[ -n $headless ]]; then
    hyprctl output remove "$headless" >/dev/null 2>&1
  fi

  local leftovers
  leftovers=$(hyprctl -j clients 2>/dev/null | jq --arg prefix "$test_prefix" '[.[] | select(.class | startswith($prefix))] | length' 2>/dev/null)
  if [[ ${leftovers:-1} -ne 0 ]]; then
    printf 'cleanup failed: %s test clients remain\n' "$leftovers" >&2
    exit 1
  fi

  local leftover_workspaces leftover_output
  leftover_workspaces=$(hyprctl -j workspaces 2>/dev/null | jq --arg prefix "$test_prefix" '[.[] | select(.name | startswith($prefix))] | length' 2>/dev/null)
  leftover_output=$(hyprctl -j monitors 2>/dev/null | jq --arg name "$headless" '[.[] | select(.name == $name)] | length' 2>/dev/null)
  if [[ ${leftover_workspaces:-1} -ne 0 || ${leftover_output:-1} -ne 0 ]]; then
    printf 'cleanup failed: %s test workspaces and %s test outputs remain\n' "$leftover_workspaces" "$leftover_output" >&2
    exit 1
  fi

  exit "$exit_code"
}

trap cleanup EXIT INT TERM

for id in "${test_ids[@]}"; do
  if workspace_exists "$id"; then
    printf 'preflight failed: workspace ID %s already exists\n' "$id" >&2
    exit 1
  fi
done

if hyprctl -j clients | jq -e --arg prefix "$test_prefix" '.[] | select(.class | startswith($prefix))' >/dev/null; then
  printf 'preflight failed: stale spike clients exist\n' >&2
  exit 1
fi

before_monitors=$(hyprctl -j monitors | jq -c '[.[].name]')
hyprctl output create headless >/dev/null
headless=$(hyprctl -j monitors | jq -r --argjson before "$before_monitors" '[.[].name | select(. as $name | $before | index($name) | not)][0] // empty')
if [[ -z $headless ]]; then
  printf 'failed to identify the temporary headless output\n' >&2
  exit 1
fi

launch() {
  local class=$1
  local workspace=$2
  dispatch "hl.dsp.exec_cmd(\"foot --app-id=$class --title=$class\", { workspace = \"$workspace silent\", monitor = \"$headless silent\", no_initial_focus = true })"
}

launch "$test_prefix-slot" "$slot"
launch "$test_prefix-a" "$home_a"
launch "$test_prefix-a2" "$home_a"
launch "$test_prefix-b" "$home_b"
wait_for_clients 4
sleep 1

headless_id=$(hyprctl -j monitors | jq -r --arg name "$headless" '.[] | select(.name == $name) | .id')
clients_off_headless=$(hyprctl -j clients | jq --arg prefix "$test_prefix" --argjson monitor "$headless_id" '[.[] | select((.class | startswith($prefix)) and .monitor != $monitor)] | length')
[[ $clients_off_headless -eq 0 ]]
printf 'PASS all test windows are isolated on %s\n' "$headless"

dispatch "hl.dsp.workspace.rename({ workspace = \"$home_a\", name = \"$test_prefix:a\" })"
dispatch "hl.dsp.workspace.rename({ workspace = \"$home_b\", name = \"$test_prefix:b\" })"

before_geometry=$(hyprctl -j clients | jq -c --arg prefix "$test_prefix-a" '[.[] | select(.class | startswith($prefix)) | {class, at, size, floating, grouped, fullscreen}] | sort_by(.class)')

dispatch "hl.dsp.workspace.rename({ workspace = \"$slot\", name = \"$test_prefix:parked:$slot\" })"
[[ $(workspace_id_by_name "$test_prefix:parked:$slot") == "$slot" ]]
dispatch "hl.dsp.workspace.rename({ workspace = \"$test_prefix:parked:$slot\", name = \"$slot\" })"

dispatch "hl.dsp.workspace.rename({ workspace = \"$slot\", name = \"$test_prefix:parked:$slot\" })"
dispatch "hl.dsp.workspace.change_id({ workspace = \"$test_prefix:parked:$slot\", id = $parking })"
[[ $(workspace_id_by_name "$test_prefix:parked:$slot") == "$parking" ]]
dispatch "hl.dsp.workspace.change_id({ workspace = \"$test_prefix:parked:$slot\", id = $slot })"
dispatch "hl.dsp.workspace.rename({ workspace = \"$test_prefix:parked:$slot\", name = \"$slot\" })"
printf 'PASS interrupted rename and parking steps are reversible\n'

dispatch "function() hl.dispatch(hl.dsp.workspace.rename({ workspace = \"$slot\", name = \"$test_prefix:parked:$slot\" })); hl.dispatch(hl.dsp.workspace.change_id({ workspace = \"$test_prefix:parked:$slot\", id = $parking })); hl.dispatch(hl.dsp.workspace.change_id({ workspace = \"$test_prefix:a\", id = $slot })) end"

[[ $(workspace_id_by_name "$test_prefix:parked:$slot") == "$parking" ]]
[[ $(workspace_id_by_name "$test_prefix:a") == "$slot" ]]

after_geometry=$(hyprctl -j clients | jq -c --arg prefix "$test_prefix-a" '[.[] | select(.class | startswith($prefix)) | {class, at, size, floating, grouped, fullscreen}] | sort_by(.class)')
[[ $before_geometry == "$after_geometry" ]]
printf 'PASS change_id preserves tiled windows, names, and geometry\n'

probe_output=$(SPIKE_OWNER_NAME="$test_prefix:a" SPIKE_PARKED_NAME="$test_prefix:parked:$slot" timeout 5s quickshell --no-color -p "$(dirname "$0")/LeaseProbe.qml" 2>&1)
[[ $probe_output == *LEASE_PROBE_OK* ]]
printf 'PASS a fresh Quickshell process reconstructs the active lease\n'

dispatch "hl.dsp.workspace.change_id({ workspace = \"$test_prefix:a\", id = $home_a })"
[[ -z $(workspace_id_by_name "$slot") ]]
dispatch "hl.dsp.workspace.change_id({ workspace = \"$test_prefix:a\", id = $slot })"
printf 'PASS interrupted owner switch is reversible\n'

dispatch "hl.dsp.focus({ workspace = \"$slot\" })"
dispatch "hl.dsp.focus({ window = \"class:$test_prefix-a\" })"
dispatch 'hl.dsp.group.toggle()'
dispatch "hl.dsp.focus({ window = \"class:$test_prefix-a2\" })"
dispatch 'hl.dsp.window.move({ into_group = "l" })'
dispatch "hl.dsp.window.fullscreen({ mode = \"fullscreen\", window = \"class:$test_prefix-a2\" })"
dispatch "hl.dsp.workspace.change_id({ workspace = \"$test_prefix:a\", id = 92 })"

grouped_count=$(hyprctl -j clients | jq --arg prefix "$test_prefix-a" '[.[] | select((.class | startswith($prefix)) and (.grouped | length == 2))] | length')
fullscreen_count=$(hyprctl -j clients | jq --arg prefix "$test_prefix-a" '[.[] | select((.class | startswith($prefix)) and .fullscreen == 2)] | length')
[[ $grouped_count -eq 2 && $fullscreen_count -eq 1 ]]
dispatch "hl.dsp.workspace.change_id({ workspace = \"$test_prefix:a\", id = $home_a })"
dispatch "hl.dsp.window.fullscreen({ mode = \"fullscreen\", window = \"class:$test_prefix-a2\" })"
printf 'PASS change_id preserves groups and fullscreen\n'

dispatch "function() hl.dispatch(hl.dsp.workspace.change_id({ workspace = \"$test_prefix:a\", id = $slot })); hl.dispatch(hl.dsp.workspace.change_id({ workspace = \"$test_prefix:a\", id = $home_a })); hl.dispatch(hl.dsp.workspace.change_id({ workspace = \"$test_prefix:b\", id = $slot })); hl.dispatch(hl.dsp.focus({ workspace = \"$slot\" })) end"
[[ $(hyprctl activeworkspace -j | jq -r '.name') == "$test_prefix:b" ]]
printf 'PASS compound dispatcher switches owner with one final focus\n'

dispatch "hl.dsp.window.float({ action = \"toggle\", window = \"class:$test_prefix-b\" })"
dispatch "hl.dsp.window.resize({ window = \"class:$test_prefix-b\", x = 700, y = 500 })"
dispatch "hl.dsp.window.move({ window = \"class:$test_prefix-b\", x = 120, y = 140 })"
dispatch "hl.dsp.workspace.change_id({ workspace = \"$test_prefix:b\", id = 93 })"
float_state=$(hyprctl -j clients | jq -c --arg class "$test_prefix-b" '.[] | select(.class == $class) | {at, size, floating}')
[[ $float_state == '{"at":[120,140],"size":[700,500],"floating":true}' ]]
dispatch "hl.dsp.workspace.change_id({ workspace = \"$test_prefix:b\", id = $slot })"
printf 'PASS change_id preserves floating geometry\n'

highest_regular=$(hyprctl -j workspaces | jq '[.[] | select(.id >= 1 and .id <= 10) | .id] | max')
dispatch "hl.dsp.focus({ workspace = \"$highest_regular\" })"
dispatch 'hl.dsp.focus({ workspace = "e+1" })'
relative_target=$(hyprctl activeworkspace -j | jq -r '.id')
if [[ $relative_target -eq $slot || $relative_target -eq $home_a || $relative_target -eq $home_b || $relative_target -eq $parking ]]; then
  printf 'FAIL relative navigation exposes internal workspaces (selected %s)\n' "$relative_target"
else
  printf 'PASS relative navigation ignored internal workspaces\n'
fi

hyprctl eval "hypr_herdr_spike_rule = hl.workspace_rule({ workspace = \"$slot\", layout = \"master\" })" >/dev/null
rule_created=true
sleep 0.1
rule_layout=$(hyprctl -j workspaces | jq -r --argjson id "$slot" '.[] | select(.id == $id) | .tiledLayout')
[[ $rule_layout == master ]]
printf 'WARN numeric workspace rules follow the leased ID and affect Herdr\n'

dispatch "hl.dsp.focus({ workspace = \"94\" })"
dispatch 'hl.dsp.workspace.rename({ workspace = "94", name = "hypr-herdr-spike:empty" })'
dispatch 'hl.dsp.workspace.change_id({ workspace = "hypr-herdr-spike:empty", id = 1000000194 })'
dispatch "hl.dsp.focus({ workspace = \"$saved_workspace\" })"
sleep 0.2
if workspace_exists 1000000194; then
  printf 'PASS empty parked workspace survived\n'
else
  printf 'FAIL empty parked workspace was destroyed after losing focus\n'
fi

dispatch "hl.dsp.workspace.change_id({ workspace = \"$test_prefix:b\", id = $home_b })"
[[ -z $(workspace_id_by_name "$slot") ]]
dispatch "hl.dsp.workspace.change_id({ workspace = \"$test_prefix:parked:$slot\", id = $slot })"
dispatch "hl.dsp.workspace.rename({ workspace = \"$test_prefix:parked:$slot\", name = \"$slot\" })"
[[ $(workspace_id_by_name "$slot") == "$slot" ]]
printf 'PASS interrupted release is recoverable from workspace metadata\n'

printf 'SLOT_LEASING_SPIKE_COMPLETE\n'
