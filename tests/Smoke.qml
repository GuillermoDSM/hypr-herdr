import QtQuick
import Quickshell
import "IdCodec.js" as IdCodec

ShellRoot {
  HerdrClient {
    id: client

    onSnapshotApplied: {
      if (state === "ready" && protocol === 20 && IdCodec.workspaceName("w1") === "herdr:dzE")
        console.log("HERDR_SMOKE_OK", state, protocol, workspaces.length, tabs.length, panes.length)
      else
        console.error("HERDR_SMOKE_FAILED", state, protocol, IdCodec.workspaceName("w1"))
      Qt.quit()
    }
  }

  Timer {
    interval: 5000
    running: true
    onTriggered: {
      console.error("HERDR_SMOKE_TIMEOUT", client.state, client.errorMessage)
      Qt.quit()
    }
  }
}
