#!/bin/bash

set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
plugin_id="guillermodsm.hypr-herdr"
plugin_dir="${OMARCHY_PLUGINS_DIR:-$HOME/.config/omarchy/plugins}/$plugin_id"

usage() {
  cat <<'EOF'
Usage: tests/dev.sh <command>

  sync            Copy the checkout into the installed plugin directory
  watch           Copy on every save (Ctrl+C to stop)
  open [spaceId]  Attach Herdr to the current workspace (or switch to spaceId)
  release         Detach: restore the original workspace and hide the sidebar
  hide            Hide the sidebar view only (keeps the lease)
  show            Show the sidebar view
  status          Print plugin, lease, preparation and panel state
  reload          Restart omarchy-shell and reload plugin code
  enable          Enable the plugin once (installation)
  disable         Disable the plugin (refuses while a lease is active)
EOF
}

sync() {
  mkdir -p "$plugin_dir"
  rsync -a --delete --exclude=.git --exclude=.gitignore "$repo_dir/" "$plugin_dir/"
}

require_plugin() {
  if ! omarchy-shell "$plugin_id" status >/dev/null 2>&1; then
    echo "Plugin '$plugin_id' is not loaded. Run: tests/dev.sh enable" >&2
    exit 1
  fi
}

case "${1:-}" in
  sync)
    sync
    echo "Synced $repo_dir -> $plugin_dir"
    ;;
  watch)
    sync
    echo "Watching $repo_dir -> $plugin_dir (Ctrl+C to stop)"
    inotifywait -m -r -q -e close_write,create,delete,move \
      --exclude '/\.git/' --format '%w%f' "$repo_dir" |
    while read -r changed; do
      rsync -a --delete --exclude=.git --exclude=.gitignore "$repo_dir/" "$plugin_dir/" >/dev/null
      echo "[dev] synced: ${changed#"$repo_dir"/}"
    done
    ;;
  open)
    require_plugin
    if [[ -n "${2:-}" ]]; then
      omarchy-shell "$plugin_id" openSpace "$2"
    else
      omarchy-shell "$plugin_id" openLast
    fi
    ;;
  release|close|detach)
    require_plugin
    omarchy-shell "$plugin_id" release
    ;;
  hide)
    require_plugin
    omarchy-shell shell hide "$plugin_id"
    ;;
  show)
    require_plugin
    omarchy-shell "$plugin_id" show
    ;;
  status)
    require_plugin
    status=$(omarchy-shell "$plugin_id" status)
    if command -v jq >/dev/null 2>&1; then
      printf '%s\n' "$status" | jq .
    else
      printf '%s\n' "$status"
    fi
    ;;
  reload)
    omarchy-restart-shell
    echo "Restarted omarchy-shell"
    ;;
  enable)
    omarchy plugin enable "$plugin_id"
    ;;
  disable)
    if command -v jq >/dev/null 2>&1 \
      && status=$(omarchy-shell "$plugin_id" status 2>/dev/null) \
      && [[ $(printf '%s' "$status" | jq -r '.lease.active // false') == "true" ]]; then
      echo "Active lease detected. Run 'tests/dev.sh release' before disabling." >&2
      exit 1
    fi
    omarchy plugin disable "$plugin_id"
    ;;
  *)
    usage
    exit 1
    ;;
esac
