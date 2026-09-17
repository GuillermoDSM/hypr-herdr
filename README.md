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
- A stable `herdr:v1:<home_id>:<base64url(space_id)>` name.
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

Herdr IDs remain opaque and are encoded as base64url. Space `w1` with home ID `1000000001` uses `herdr:v1:1000000001:dzE`. While leased, its name also carries the slot, original name, and parking ID so a fresh process can recover the transaction.

## Project Status

This repository is an early implementation. The existing vertical slice provides:

- Herdr protocol 20 and 22 snapshots over its Unix socket.
- Event subscriptions with debounced authoritative refreshes.
- Reconnection with bounded exponential backoff.
- A themed, resizable layer-shell sidebar for spaces and global agent states.
- Event-driven preparation with one managed terminal window per Herdr pane.
- Omarchy IPC methods for navigation and diagnostics.

The Workspace Slot Leasing spike is complete with a go decision. Empty workspaces are disposable: if an empty original disappears while parked, the leased Herdr workspace retains enough metadata for `release` to recreate it. No persistent rule or sentinel window is needed. See [SLOT_LEASING_SPIKE.md](SLOT_LEASING_SPIKE.md).

## Requirements

- Omarchy 4 with plugin schema version 1.
- Herdr 0.8.2 (protocol 20) or Herdr 0.9.1 (protocol 22).
- Quickshell with `Quickshell.Io.Socket` and `Quickshell.Hyprland`.
- Hyprland 0.56 or a compatible version exposing `hl.dsp.workspace.change_id`.
- `xdg-terminal-exec` and `uwsm-app` for managed terminal windows.

The coordinator requires Hyprland's Lua config provider before mutating a workspace. Hyprland 0.56 is the supported baseline for `change_id`.

## Required Spike

Status: **completed, GO with disposable empty workspaces**. The reversible harnesses are `tests/slot-leasing-spike.sh` and `tests/disposable-empty-spike.sh`; results are documented in [SLOT_LEASING_SPIKE.md](SLOT_LEASING_SPIKE.md).

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
qmllint -I /usr/share/omarchy/shell -I /usr/lib/qt6/qml Panel.qml HerdrClient.qml WorkspaceLease.qml WorkspaceManager.qml
bash tests/smoke.sh
bash tests/panel-smoke.sh
bash tests/lease-coordinator-smoke.sh
bash tests/lease-repeat-smoke.sh
bash tests/workspace-manager-smoke.sh
```

Then install the checkout as a real directory and enable it once:

```bash
tests/dev.sh sync
omarchy-shell shell rescanPlugins
omarchy plugin enable guillermodsm.hypr-herdr
```

The plugin directory must be a real directory, not a symlink: Omarchy hot-reloads plugin code with an `inotifywait -r` watcher that does not traverse symlinked plugin folders. During iteration keep the plugin enabled and sync the checkout after each save:

```bash
tests/dev.sh sync     # one-shot copy
tests/dev.sh watch    # copy on every save (Ctrl+C to stop)
```

Omarchy reloads the panel automatically when files change under `~/.config/omarchy/plugins/`; if a changed QML component remains cached, `tests/dev.sh reload` restarts `omarchy-shell` through Omarchy's official command. Managed terminal windows remain in Hyprland and are adopted by the new shell instance. `tests/dev.sh` also exposes `open`, `release`, `status`, `hide`, `show`, `enable` and `disable`.

## Development lifecycle

Three planes stay independent:

- **Installation.** `omarchy plugin enable/disable` is installation only. With `keepLoaded`, the plugin stays mounted between summons, so opening and closing Herdr never requires enable/disable. `disable` requires releasing the lease first.
- **Lease.** `openLast` from a numeric workspace exposes the last Herdr space in that slot. `release` (or the same `openLast` toggle from the leased workspace) detaches: the space returns to its home ID, the original workspace is restored, and the sidebar hides. The plugin remains loaded and connected, so reopening is immediate.
- **View.** `close` or `omarchy-shell shell hide guillermodsm.hypr-herdr` only hides the sidebar. It never releases the lease; the sidebar reappears when the leased workspace is focused again.

The sidebar mirrors Herdr's hierarchy: spaces are listed at the top and agents at the bottom. Drag its right edge to resize it. The saved value is a fraction of the current monitor width, clamped to practical minimum and maximum sizes, so it remains usable after a resolution or scale change.

Direct attach applications may enable terminal mouse reporting. In that mode, use the terminal emulator's bypass modifier to select text, commonly `Shift` while dragging. Hypr Herdr launches the user's configured terminal through `xdg-terminal-exec` and does not install emulator-specific mouse mappings.

`SUPER+W` keeps its native "Close window" behavior. The sidebar is a layer-shell surface with no keyboard focus, so compositor bindings never reach it. Detach is the Herdr entry binding, which acts as a toggle from the leased workspace.

## IPC

The IPC surface is:

```bash
omarchy-shell guillermodsm.hypr-herdr openLast
omarchy-shell guillermodsm.hypr-herdr openSpace w1
omarchy-shell guillermodsm.hypr-herdr focusPane w1:p1
omarchy-shell guillermodsm.hypr-herdr release
omarchy-shell guillermodsm.hypr-herdr status
omarchy-shell guillermodsm.hypr-herdr reconcile
omarchy-shell guillermodsm.hypr-herdr close
omarchy-shell guillermodsm.hypr-herdr show
```

From a regular numeric workspace, `openLast` acquires that slot or migrates the existing lease to it. From the Herdr workspace that owns the slot, `openLast` acts as a toggle and releases the lease. `openSpace` switches the owner of the leased slot, or migrates the lease when invoked from another numeric slot. If preparation is still running, retry after `status` reports `preparation.state` as `ready`. `release` returns the active Herdr space to its home ID, restores the original workspace and closes the sidebar view. `close` only hides the sidebar view; `show` brings it back without touching the lease.

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

An emergency recovery command remains Sprint 4 work. Until then, Workspace Slot Leasing should only be tested with disposable workspace IDs.

## Current Limits

- Lease Coordinator is implemented and tested on disposable headless workspaces.
- Spaces without panes reserve a home ID but have no physical workspace until a pane exists.
- Production leasing has not been enabled against normal workspaces yet.
- Relative navigation may visit internal Herdr or parked workspaces in v0.1.
- The sidebar currently targets the default output; per-output instances are pending.
- The first leasing version supports one global slot, not one slot per monitor.
- A manually closed pane window is recreated only when its pane or space is selected again.
- Existing pane windows are adopted only by their exact stable `app-id`; foreign windows are never closed.
- In-process shell reloads retain the pane-to-terminal attachment inventory, so existing windows are not silently adopted for a different `terminal_id`.
- Incremental events trigger a fresh snapshot rather than mutating the local model in place.

## License

MIT
