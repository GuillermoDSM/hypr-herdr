import QtQuick
import Quickshell
import Quickshell.Hyprland
import "IdCodec.js" as IdCodec

ShellRoot {
  id: root
  property int step: 0
  property bool productionCommandValid: false
  property var spaces: [
    { workspace_id: "manager-smoke-a", label: "A" },
    { workspace_id: "manager-smoke-b", label: "B" }
  ]
  property var panes: [
    { pane_id: "manager-smoke:p1", terminal_id: "term-smoke-1", workspace_id: "manager-smoke-a", cwd: "/tmp" },
    { pane_id: "manager-smoke:p2", terminal_id: "term-smoke-2", workspace_id: "manager-smoke-a", cwd: "/tmp" }
  ]

  WorkspaceManager {
    id: commandManager
  }

  Component.onCompleted: {
    var command = commandManager.commandForPane({
      pane_id: "pane'quoted",
      terminal_id: "term'quoted",
      cwd: "/tmp/path with spaces"
    })
    productionCommandValid = command.indexOf("'uwsm-app' '--' 'xdg-terminal-exec'") === 0
      && command.indexOf("'herdr' 'terminal' 'attach'") !== -1
      && command.indexOf("'--takeover'") !== -1
      && command.indexOf("'term'\\''quoted'") !== -1
  }

  WorkspaceManager {
    id: manager
    enabled: true
    spaces: root.spaces
    panes: root.panes
    testLauncher: Quickshell.env("HYPR_HERDR_TEST_LAUNCHER") || ""
    testHomeBase: 1100000301

    onReconciliationComplete: {
      if (step === 0 && ready && spaceReady("manager-smoke-a")) {
        step = 10
        closeTop(topsForAppId(IdCodec.appId("manager-smoke:p2"))[0], IdCodec.appId("manager-smoke:p2"))
        manualCloseTimer.restart()
      } else if (step === 11 && ready && spaceReady("manager-smoke-a")) {
        step = 1
        root.panes = [
          { pane_id: "manager-smoke:p1", terminal_id: "term-smoke-1", workspace_id: "manager-smoke-b", cwd: "/tmp" },
          { pane_id: "manager-smoke:p2", terminal_id: "term-smoke-2", workspace_id: "manager-smoke-a", cwd: "/tmp" }
        ]
        reconcile()
      } else if (step === 1 && ready && spaceReady("manager-smoke-a") && spaceReady("manager-smoke-b")) {
        var moved = topsForAppId(IdCodec.appId("manager-smoke:p1"))
        var movedWorkspace = workspaceById(1100000302)
        if (moved.length !== 1 || topWorkspaceId(moved[0]) !== 1100000302
            || !movedWorkspace
            || workspaceName(movedWorkspace) !== "herdr:v1:1100000302:bWFuYWdlci1zbW9rZS1i") {
          console.error("WORKSPACE_MANAGER_FAILED", "pane movement state")
          Qt.quit()
          return
        }
        console.log("WORKSPACE_MANAGER_MOVED")
        step = 2
        root.panes = []
        reconcile()
      } else if (step === 2 && ready
                 && topsForAppId(IdCodec.appId("manager-smoke:p1")).length === 0
                 && topsForAppId(IdCodec.appId("manager-smoke:p2")).length === 0
                 && root.productionCommandValid) {
        console.log("WORKSPACE_MANAGER_OK")
        Qt.quit()
      }
    }
  }

  Timer {
    id: manualCloseTimer
    interval: 500
    repeat: false
    onTriggered: {
      if (manager.topsForAppId(IdCodec.appId("manager-smoke:p2")).length !== 0) {
        console.error("WORKSPACE_MANAGER_FAILED", "managed terminal did not close")
        Qt.quit()
        return
      }
      step = 11
      if (manager.focusPane("manager-smoke:p2") !== "preparing") {
        console.error("WORKSPACE_MANAGER_FAILED", "closed pane did not request recreation")
        Qt.quit()
      }
    }
  }

  Timer {
    interval: 12000
    running: true
    onTriggered: {
      var tops = []
      var values = Hyprland.toplevels.values
      for (var i = 0; i < values.length; i++) {
        var ipc = values[i].lastIpcObject || {}
        tops.push(String(ipc.address || values[i].address || "") + "="
                  + String(ipc.class || ipc.initialClass || ""))
      }
      console.error("WORKSPACE_MANAGER_FAILED", root.step, manager.state, manager.errorMessage,
                    manager.pendingPaneId, manager.attachedPaneCount, manager.pendingCommand,
                    tops.join(","))
      Qt.quit()
    }
  }
}
