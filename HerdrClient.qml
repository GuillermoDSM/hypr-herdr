import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root
  visible: false

  readonly property int supportedProtocol: 20
  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || home + "/.config"
  readonly property string sessionName: Quickshell.env("HERDR_SESSION") || ""
  property string socketPath: Quickshell.env("HERDR_SOCKET_PATH")
    || (sessionName === "" || sessionName === "default"
      ? configHome + "/herdr/herdr.sock"
      : configHome + "/herdr/sessions/" + sessionName + "/herdr.sock")
  property bool running: true

  property string state: "connecting"
  property string errorMessage: ""
  property string serverVersion: ""
  property int protocol: 0
  property var workspaces: []
  property var tabs: []
  property var panes: []
  property var agents: []
  property string focusedWorkspaceId: ""
  property string focusedTabId: ""
  property string focusedPaneId: ""
  property double lastSnapshotAt: 0
  property int revision: 0

  property bool eventWanted: false
  property bool snapshotWanted: false
  property bool snapshotPending: false
  property string subscribedPaneKey: ""
  property int retryDelayMs: 1000
  property int requestSequence: 0

  signal snapshotApplied()

  function paneKey() {
    var ids = []
    for (var i = 0; i < panes.length; i++) ids.push(String(panes[i].pane_id || ""))
    ids.sort()
    return ids.join("\n")
  }

  function subscriptions() {
    var names = [
      "workspace.created", "workspace.updated", "workspace.metadata_updated", "workspace.closed",
      "workspace.renamed", "workspace.moved", "workspace.reordered",
      "workspace.focused", "tab.created", "tab.closed", "tab.renamed", "tab.focused",
      "tab.moved", "pane.created", "pane.closed", "pane.updated", "pane.focused", "pane.moved",
      "pane.exited", "pane.agent_detected", "layout.updated"
    ]
    var result = []
    for (var i = 0; i < names.length; i++) result.push({ type: names[i] })
    for (var j = 0; j < panes.length; j++) {
      var paneId = String(panes[j].pane_id || "")
      if (paneId !== "") result.push({ type: "pane.agent_status_changed", pane_id: paneId })
    }
    return result
  }

  function subscribe() {
    subscribedPaneKey = paneKey()
    var request = {
      id: "hypr-herdr:subscribe:" + (++requestSequence),
      method: "events.subscribe",
      params: { subscriptions: subscriptions() }
    }
    eventSocket.write(JSON.stringify(request) + "\n")
    eventSocket.flush()
    eventAckTimeout.restart()
  }

  function requestSnapshot() {
    if (!running) return
    if (snapshotWanted || snapshotSocket.connected) {
      snapshotPending = true
      return
    }
    snapshotPending = false
    snapshotWanted = true
  }

  function handleEventLine(line) {
    var message
    try {
      message = JSON.parse(String(line || ""))
    } catch (error) {
      console.warn("hypr-herdr", "Invalid event frame", error)
      return
    }

    if (message.error) {
      fail(String(message.error.message || "Herdr rejected the subscription"))
      return
    }
    if (message.result && message.result.type === "subscription_started") {
      eventAckTimeout.stop()
      requestSnapshot()
      return
    }
    if (message.event) refreshDebounce.restart()
  }

  function handleSnapshotLine(line) {
    snapshotTimeout.stop()
    snapshotWanted = false
    var message
    try {
      message = JSON.parse(String(line || ""))
    } catch (error) {
      fail("Herdr returned an invalid snapshot")
      return
    }

    if (message.error) {
      fail(String(message.error.message || "Herdr rejected the snapshot request"))
      return
    }

    var result = message.result || {}
    var snapshot = result.snapshot || null
    if (!snapshot) {
      fail("Herdr returned an empty snapshot")
      return
    }

    protocol = Number(snapshot.protocol || 0)
    serverVersion = String(snapshot.version || "")
    if (protocol !== supportedProtocol) {
      state = "incompatible"
      errorMessage = "Herdr protocol " + protocol + " is not supported (expected " + supportedProtocol + ")"
      eventWanted = false
      return
    }

    workspaces = Array.isArray(snapshot.workspaces) ? snapshot.workspaces : []
    tabs = Array.isArray(snapshot.tabs) ? snapshot.tabs : []
    panes = Array.isArray(snapshot.panes) ? snapshot.panes : []
    agents = Array.isArray(snapshot.agents) ? snapshot.agents : []
    focusedWorkspaceId = String(snapshot.focused_workspace_id || "")
    focusedTabId = String(snapshot.focused_tab_id || "")
    focusedPaneId = String(snapshot.focused_pane_id || "")
    lastSnapshotAt = Date.now()
    errorMessage = ""
    state = "ready"
    retryDelayMs = 1000
    revision++
    snapshotApplied()

    if (subscribedPaneKey !== paneKey()) restartEvents()
    if (snapshotPending) snapshotAgain.restart()
  }

  function fail(message) {
    eventAckTimeout.stop()
    snapshotTimeout.stop()
    errorMessage = message
    if (state !== "incompatible") state = "disconnected"
    snapshotWanted = false
    eventWanted = false
    if (running && state !== "incompatible") reconnectTimer.restart()
  }

  function restartEvents() {
    eventWanted = false
    if (running && state !== "incompatible") reconnectTimer.restart()
  }

  function reconnectNow() {
    state = workspaces.length > 0 ? "reconnecting" : "connecting"
    eventWanted = true
  }

  Component.onCompleted: reconnectNow()

  Timer {
    id: reconnectTimer
    interval: root.retryDelayMs
    repeat: false
    onTriggered: {
      root.retryDelayMs = Math.min(30000, root.retryDelayMs * 2)
      root.reconnectNow()
    }
  }

  Timer {
    id: eventAckTimeout
    interval: 5000
    repeat: false
    onTriggered: root.fail("Herdr did not acknowledge the event subscription")
  }

  Timer {
    id: snapshotTimeout
    interval: 5000
    repeat: false
    onTriggered: root.fail("Herdr did not return a snapshot")
  }

  Timer {
    id: snapshotAgain
    interval: 10
    repeat: false
    onTriggered: {
      if (snapshotSocket.connected) {
        restart()
        return
      }
      root.snapshotPending = false
      root.requestSnapshot()
    }
  }

  Timer {
    id: refreshDebounce
    interval: 80
    repeat: false
    onTriggered: root.requestSnapshot()
  }

  Socket {
    id: eventSocket
    path: root.socketPath
    connected: root.running && root.eventWanted

    onConnectionStateChanged: {
      if (connected) root.subscribe()
      else if (root.running && root.eventWanted && root.state !== "incompatible") root.fail("Herdr disconnected")
    }
    onError: function(error) { root.fail("Cannot connect to Herdr at " + root.socketPath) }

    parser: SplitParser {
      splitMarker: "\n"
      onRead: function(line) { root.handleEventLine(line) }
    }
  }

  Socket {
    id: snapshotSocket
    path: root.socketPath
    connected: root.running && root.snapshotWanted

    onConnectionStateChanged: if (connected) {
      var request = {
        id: "hypr-herdr:snapshot:" + (++root.requestSequence),
        method: "session.snapshot",
        params: {}
      }
      write(JSON.stringify(request) + "\n")
      flush()
      snapshotTimeout.restart()
    }
    onError: function(error) { root.fail("Cannot read the Herdr session") }

    parser: SplitParser {
      splitMarker: "\n"
      onRead: function(line) { root.handleSnapshotLine(line) }
    }
  }
}
