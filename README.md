# hypr-herdr

Hypr Herdr integrates Herdr spaces with Omarchy through **Workspace Slot Leasing**. A prepared Herdr workspace temporarily assumes the numeric ID of the workspace where Herdr was opened, so Hyprland's native number bindings and Omarchy's standard workspace bar continue to work unchanged.

```text
The number is a slot.
The workspace is the content.
Hypr Herdr leases the slot to the active space.
```

If Herdr is opened from workspace `2`, the original workspace is parked at an internal positive ID and the selected Herdr space assumes ID `2`. `SUPER+3` still opens workspace `3`, and `SUPER+2` returns directly to Herdr without plugin redirection. Releasing the lease restores the original workspace `2`.

The complete product and recovery design is in [PRD.md](PRD.md).

## Architecture

Each Herdr space owns a normal Hyprland workspace with:

- A stable high positive home ID.
- A stable `herdr:<base64url(space_id)>` name.
- Its terminal windows and native Hyprland layout.

The active space exchanges its home ID for the leased numeric slot through Hyprland 0.56's Lua dispatcher:

```lua
hl.dsp.workspace.change_id({
  workspace = workspace,
  id = newId
})
```

The original numeric workspace is renamed with recovery metadata and parked at another free positive ID. Switching Herdr spaces swaps which complete workspace owns the slot; individual windows are never transported between workspaces.

This design does not replace:

- `SUPER+1..9` bindings.
- Omarchy's standard workspace widget.
- Hyprland or Omarchy components.

Herdr IDs remain opaque and are encoded as base64url in workspace names and terminal app-ids. For example, space `w1` uses the stable name `herdr:dzE`, regardless of whether its current ID is its internal home ID or a leased slot.

## Project Status

This repository is an early implementation. The existing vertical slice provides:

- Herdr protocol 20 snapshots over its Unix socket.
- Event subscriptions with debounced authoritative refreshes.
- Reconnection with bounded exponential backoff.
- A themed layer-shell sidebar for spaces, tabs, panes, and agent states.
- Omarchy IPC methods for navigation and diagnostics.

The Workspace Slot Leasing spike is complete and produced a no-go for the architecture as currently specified. High internal IDs interfere with relative navigation on the same monitor, and an empty parked workspace is destroyed after losing focus. See [SLOT_LEASING_SPIKE.md](SLOT_LEASING_SPIKE.md). Automatic terminal creation and `--takeover` remain disabled until safe ownership and recovery checks are implemented.

## Requirements

- Omarchy 4 with plugin schema version 1.
- Herdr 0.8.2 with protocol 20.
- Quickshell with `Quickshell.Io.Socket` and `Quickshell.Hyprland`.
- Hyprland 0.56 or a compatible version exposing `hl.dsp.workspace.change_id`.
- `xdg-terminal-exec` and `uwsm-app` for managed terminal windows.

The plugin must verify `change_id` support before mutating any workspace. Unsupported versions must fail without parking or renaming the current workspace.

## Required Spike

Status: **completed, NO-GO**. The reproducible harness is `tests/slot-leasing-spike.sh`; results and cleanup guarantees are documented in [SLOT_LEASING_SPIKE.md](SLOT_LEASING_SPIKE.md).

Workspace Slot Leasing must pass an isolated spike before the implementation is considered stable. The spike must verify:

- ID changes preserve windows, native layout, groups, fullscreen, and renamed workspace names.
- Lease acquisition and Herdr space switching show no intermediate visual state.
- Native numeric bindings and the standard workspace bar need no customization.
- High internal IDs do not make relative navigation such as `SUPER+TAB` unusable.
- Numeric workspace rules behave predictably while Herdr owns a slot.
- Reloading `omarchy-shell` can adopt or safely recover an active lease.
- Every partially completed transaction can be recovered.
- A documented emergency procedure can restore the original workspace without loading the panel.
- Single-monitor and multi-monitor behavior is understood.

See [PRD.md](PRD.md#spike-obligatorio) for the full validation gate and fallback architecture.

## Install

Once this repository is published:

```bash
omarchy plugin add https://github.com/guillermodsm/hypr-herdr.git --enable --yes
```

For local development, validate the checkout first:

```bash
omarchy plugin validate .
qmllint -I /usr/share/omarchy/shell -I /usr/lib/qt6/qml Panel.qml HerdrClient.qml
bash tests/smoke.sh
bash tests/panel-smoke.sh
```

Then symlink or clone it as `~/.config/omarchy/plugins/guillermodsm.hypr-herdr` and enable it with Omarchy's standard plugin command.

## IPC

The target IPC surface is:

```bash
omarchy-shell guillermodsm.hypr-herdr openLast
omarchy-shell guillermodsm.hypr-herdr openSpace w1
omarchy-shell guillermodsm.hypr-herdr focusPane w1:p1
omarchy-shell guillermodsm.hypr-herdr release
omarchy-shell guillermodsm.hypr-herdr status
omarchy-shell guillermodsm.hypr-herdr reconcile
```

From a regular numeric workspace, `openLast` acquires that slot or migrates the existing lease to it. From the Herdr workspace that owns the slot, `openLast` acts as a toggle and releases the lease. `openSpace` switches the Herdr space occupying the leased slot. `release` returns the active Herdr space to its home ID and restores the original workspace. `status` must report the leased slot, owning space, home ID, parking ID, and recovery state.

The default Herdr socket is `~/.config/herdr/herdr.sock`. `HERDR_SOCKET_PATH` takes precedence, and `HERDR_SESSION` selects `~/.config/herdr/sessions/<name>/herdr.sock` for named sessions.

## Keybinding

The only intended binding override is the Herdr entry action:

```lua
hl.unbind("SUPER + CTRL + RETURN")
o.bind(
  "SUPER + CTRL + RETURN",
  "Hypr Herdr",
  "omarchy-shell guillermodsm.hypr-herdr openLast"
)
```

Numeric workspace bindings remain native and unchanged. The plugin never modifies files under `/usr/share/omarchy/`.

## Recovery Contract

An active lease must be reconstructible from Hyprland state:

- Herdr workspaces retain `herdr:*` names while IDs change.
- The parked original workspace contains its slot, original name, and transaction token in a reserved name.
- Plugin reload adopts a complete lease or blocks further mutations when it detects a partial transaction.
- `release` is idempotent and restores the original slot and name.
- Disabling or uninstalling the plugin requires releasing an active lease first.

The emergency recovery command will be documented after the spike confirms the exact supported dispatcher sequence. Until then, Workspace Slot Leasing should only be tested with disposable workspace IDs.

## Current Limits

- Workspace Slot Leasing and release are not implemented yet.
- Lease Coordinator implementation is blocked by the completed no-go spike.
- The current code still contains direct named-workspace navigation until a replacement architecture is selected.
- The sidebar currently targets the default output; per-output instances are pending.
- The first leasing version supports one global slot, not one slot per monitor.
- Pane windows are focused only when already attached with the expected app-id.
- Terminal creation, adoption, movement, and closure reconciliation are pending a safe ownership check.
- Incremental events trigger a fresh snapshot rather than mutating the local model in place.

## License

MIT
