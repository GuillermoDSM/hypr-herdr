#!/bin/bash

set -euo pipefail

slot=191
empty_space_slot=192
home=1000000191
other_home=1000000192
parking=1000000291
prefix="hypr-herdr-spike-v2"
classes=("$prefix-owner" "$prefix-other")
test_ids=($slot $empty_space_slot $home $other_home $parking)
saved_workspace=$(hyprctl activeworkspace -j | jq -r '.id')
headless=""

dispatch() {
  hyprctl dispatch "$1" >/dev/null
}

workspace_exists() {
  local id=$1
  hyprctl -j workspaces | jq -e --argjson id "$id" '.[] | select(.id == $id)' >/dev/null
}

workspace_id_by_name() {
  local name=$1
  hyprctl -j workspaces | jq -r --arg name "$name" '[.[] | select(.name == $name) | .id][0] // empty'
}

wait_for_clients() {
  for _ in $(seq 1 50); do
    local count
    count=$(hyprctl -j clients | jq --arg prefix "$prefix" '[.[] | select(.class | startswith($prefix))] | length')
    [[ $count -eq 2 ]] && return 0
    sleep 0.1
  done
  return 1
}

cleanup() {
  local exit_code=$?
  trap - EXIT INT TERM
  set +e

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

  local clients workspaces outputs
  clients=$(hyprctl -j clients 2>/dev/null | jq --arg prefix "$prefix" '[.[] | select(.class | startswith($prefix))] | length' 2>/dev/null)
  workspaces=$(hyprctl -j workspaces 2>/dev/null | jq --arg prefix "$prefix" '[.[] | select(.name | startswith($prefix))] | length' 2>/dev/null)
  outputs=$(hyprctl -j monitors 2>/dev/null | jq --arg name "$headless" '[.[] | select(.name == $name)] | length' 2>/dev/null)
  if [[ ${clients:-1} -ne 0 || ${workspaces:-1} -ne 0 || ${outputs:-1} -ne 0 ]]; then
    printf 'cleanup failed: clients=%s workspaces=%s outputs=%s\n' "$clients" "$workspaces" "$outputs" >&2
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

launch "$prefix-owner" "$home"
launch "$prefix-other" "$other_home"
wait_for_clients
sleep 1

headless_id=$(hyprctl -j monitors | jq -r --arg name "$headless" '.[] | select(.name == $name) | .id')
off_headless=$(hyprctl -j clients | jq --arg prefix "$prefix" --argjson monitor "$headless_id" '[.[] | select((.class | startswith($prefix)) and .monitor != $monitor)] | length')
[[ $off_headless -eq 0 ]]
printf 'PASS test windows isolated on %s\n' "$headless"

stable_name="$prefix:home:$home:space:w1"
leased_name="$prefix:leased:$home:$slot:original:$slot"
dispatch "hl.dsp.workspace.rename({ workspace = \"$home\", name = \"$stable_name\" })"
dispatch "hl.dsp.workspace.rename({ workspace = \"$other_home\", name = \"$prefix:home:$other_home:space:w2\" })"

dispatch "hl.dsp.focus({ monitor = \"$headless\" })"
dispatch "hl.dsp.focus({ workspace = \"$slot\" })"
[[ $(hyprctl activeworkspace -j | jq -r '.id') == "$slot" ]]

dispatch "function() local source = hl.get_active_workspace(); hl.dispatch(hl.dsp.workspace.rename({ workspace = source, name = \"$prefix:parked:$slot\" })); hl.dispatch(hl.dsp.workspace.change_id({ workspace = source, id = $parking })); hl.dispatch(hl.dsp.workspace.rename({ workspace = \"$stable_name\", name = \"$leased_name\" })); hl.dispatch(hl.dsp.workspace.change_id({ workspace = \"$leased_name\", id = $slot })); hl.dispatch(hl.dsp.focus({ workspace = \"$slot\" })) end"
sleep 0.2

[[ $(workspace_id_by_name "$leased_name") == "$slot" ]]
if workspace_exists "$parking"; then
  printf 'FAIL empty origin unexpectedly survived without persistence\n' >&2
  exit 1
fi
printf 'PASS empty origin is disposable after acquire\n'

probe_output=$(SPIKE_OWNER_NAME="$leased_name" SPIKE_PARKED_NAME="$prefix:parked:$slot" SPIKE_PARKED_OPTIONAL=1 timeout 5s quickshell --no-color -p "$(dirname "$0")/LeaseProbe.qml" 2>&1)
[[ $probe_output == *LEASE_PROBE_OK* ]]
printf 'PASS fresh process reconstructs lease without parked workspace\n'

dispatch "hl.dsp.focus({ workspace = \"$slot\" })"
dispatch 'hl.dsp.focus({ workspace = "e+1" })'
[[ $(hyprctl activeworkspace -j | jq -r '.id') == "$other_home" ]]
dispatch 'hl.dsp.focus({ workspace = "previous" })'
[[ $(hyprctl activeworkspace -j | jq -r '.id') == "$slot" ]]
printf 'PASS relative navigation reaches a Herdr home and previous returns\n'

dispatch "function() hl.dispatch(hl.dsp.workspace.rename({ workspace = \"$leased_name\", name = \"$stable_name\" })); hl.dispatch(hl.dsp.workspace.change_id({ workspace = \"$stable_name\", id = $home })); hl.dispatch(hl.dsp.focus({ workspace = \"$slot\" })) end"
sleep 0.2

restored=$(hyprctl activeworkspace -j)
[[ $(jq -r '.id' <<<"$restored") == "$slot" ]]
[[ $(jq -r '.name' <<<"$restored") == "$slot" ]]
[[ $(jq -r '.windows' <<<"$restored") == 0 ]]
[[ $(workspace_id_by_name "$stable_name") == "$home" ]]
printf 'PASS release recreates the original empty workspace\n'

dispatch "hl.dsp.focus({ workspace = \"$empty_space_slot\" })"
dispatch "hl.dsp.workspace.rename({ workspace = \"$empty_space_slot\", name = \"$prefix:leased-empty:$empty_space_slot\" })"
[[ $(hyprctl activeworkspace -j | jq -r '.name') == "$prefix:leased-empty:$empty_space_slot" ]]
dispatch "hl.dsp.workspace.rename({ workspace = \"$prefix:leased-empty:$empty_space_slot\", name = \"$empty_space_slot\" })"
[[ $(hyprctl activeworkspace -j | jq -r '.name') == "$empty_space_slot" ]]
printf 'PASS an empty Herdr space can reuse the current empty workspace\n'

printf 'DISPOSABLE_EMPTY_SPIKE_COMPLETE\n'
