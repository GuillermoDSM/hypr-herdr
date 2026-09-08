import QtQuick
import Quickshell

ShellRoot {
  Panel {
    id: panel
    manifest: ({ id: "guillermodsm.hypr-herdr" })
    preparationEnabled: false
  }

  Timer {
    interval: 3000
    running: true
    onTriggered: {
      var status = JSON.parse(panel.statusJson())
      if (status.state === "ready" && status.protocol === 20)
        console.log("PANEL_SMOKE_OK", status.workspaces, status.tabs, status.panes)
      else
        console.error("PANEL_SMOKE_FAILED", panel.statusJson())
      Qt.quit()
    }
  }
}
