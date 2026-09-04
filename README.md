# hypr-herdr

Hypr Herdr presents Herdr spaces as named Hyprland workspaces and keeps a native Omarchy sidebar synchronized with Herdr's public socket API.

This repository is an early implementation of the design in [PRD.md](PRD.md). The current vertical slice includes:

- Herdr protocol 20 snapshots over its Unix socket.
- Event subscriptions with debounced authoritative refreshes.
- Reconnection with bounded exponential backoff.
- A themed layer-shell sidebar for spaces, tabs, panes, and agent states.
- Named workspace navigation through Quickshell's Hyprland dispatcher.
- Omarchy IPC methods for navigation and diagnostics.

Automatic terminal creation and `--takeover` are intentionally not enabled yet. The plugin can focus a pane window that already uses its expected stable app-id, but it will not take ownership of an unrelated direct attachment.

## Requirements

- Omarchy 4 with plugin schema version 1.
- Herdr 0.8.2 with protocol 20.
- Quickshell with `Quickshell.Io.Socket` and `Quickshell.Hyprland`.
- Hyprland with named workspace support.

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

Then symlink or clone it as `~/.config/omarchy/plugins/guillermodsm.hypr-herdr` and enable that plugin with Omarchy's standard plugin command.

## IPC

```bash
omarchy-shell guillermodsm.hypr-herdr openLast
omarchy-shell guillermodsm.hypr-herdr openSpace w1
omarchy-shell guillermodsm.hypr-herdr focusPane w1:p1
omarchy-shell guillermodsm.hypr-herdr status
omarchy-shell guillermodsm.hypr-herdr reconcile
```

Herdr IDs are opaque. The plugin encodes them as base64url before using them in workspace names or terminal app-ids. For example, space `w1` maps to a workspace named `herdr:dzE` and is focused through the selector `name:herdr:dzE`.

The default socket is `~/.config/herdr/herdr.sock`. `HERDR_SOCKET_PATH` takes precedence, and `HERDR_SESSION` selects `~/.config/herdr/sessions/<name>/herdr.sock` for named sessions.

## Keybinding

The intended Omarchy binding calls:

```lua
hl.unbind("SUPER + CTRL + RETURN")
o.bind(
  "SUPER + CTRL + RETURN",
  "Hypr Herdr",
  "omarchy-shell guillermodsm.hypr-herdr openLast"
)
```

Apply this override in your personal Hyprland bindings. The plugin never modifies files under `/usr/share/omarchy/`.

## Current Limits

- The sidebar currently targets the default output; per-output instances are pending.
- Pane windows are focused only when already attached with the expected app-id.
- Terminal creation, adoption, movement, and closure reconciliation are pending a safe ownership check.
- Incremental events trigger a fresh snapshot rather than mutating the local model in place.

## License

MIT
