import QtQuick
import Quickshell

ShellRoot {
  property bool createRequested: false
  property bool createResponseReceived: false
  property string createdWorkspaceId: ""
  property string requestedCwd: Quickshell.env("HOME") + "/projects/hypr-herdr"

  function finishOk() {
    console.log("WORKSPACE_CREATE_SMOKE_OK", createdWorkspaceId, client.tabs.length, client.panes.length)
    Qt.quit()
  }

  function finishFailed(message) {
    console.error("WORKSPACE_CREATE_SMOKE_FAILED", message)
    Qt.quit()
  }

  function createdPaneHasTerminal() {
    for (var i = 0; i < client.panes.length; i++) {
      var pane = client.panes[i]
      if (String(pane.workspace_id || "") === createdWorkspaceId
          && String(pane.terminal_id || "") !== ""
          && String(pane.cwd || "") === requestedCwd) return true
    }
    return false
  }

  HerdrClient {
    id: client

    onSnapshotApplied: {
      if (client.state !== "ready") return
      if (!createRequested) {
        createRequested = true
        var result = client.createWorkspace(requestedCwd)
        if (result !== "requested") finishFailed(result)
        return
      }
      if (createResponseReceived && createdPaneHasTerminal()) finishOk()
    }

    onWorkspaceCreated: function(workspaceId) {
      createdWorkspaceId = String(workspaceId || "")
      if (createdWorkspaceId === "") {
        finishFailed("Herdr returned no workspace ID")
        return
      }
      createResponseReceived = true
      client.requestSnapshot()
    }

    onWorkspaceCreateFailed: function(message) { finishFailed(message) }
  }

  Timer {
    interval: 15000
    running: true
    onTriggered: finishFailed("timeout: " + client.errorMessage)
  }
}
