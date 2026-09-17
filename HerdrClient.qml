import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root
  visible: false

  readonly property var supportedProtocols: [20, 22]
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
  property var layouts: []
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
  property var mutationQueue: []
  property bool mutationWanted: false
  property string mutationId: ""

  signal snapshotApplied()
  signal mutationFailed(string message)

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

  function protocolSupported(value) {
    return supportedProtocols.indexOf(Number(value)) !== -1
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

  function setLayoutRatios(updates) {
    if (!Array.isArray(updates) || updates.length === 0) return
    var next = mutationQueue.slice()
    for (var i = 0; i < updates.length; i++) {
      var update = updates[i] || {}
      if (!update.tabId || !Array.isArray(update.path) || !isFinite(Number(update.ratio))) continue
      next.push({
        id: "hypr-herdr:layout-ratio:" + (++requestSequence),
        method: "layout.set_split_ratio",
        params: {
          tab_id: String(update.tabId),
          path: update.path,
          ratio: Math.max(0.05, Math.min(0.95, Number(update.ratio)))
        }
      })
    }
    mutationQueue = next
    startNextMutation()
  }

  function startNextMutation() {
    if (!running || mutationWanted || mutationQueue.length === 0) return
    mutationWanted = true
  }

  function handleMutationLine(line) {
    var message = null
    try { message = JSON.parse(String(line || "")) } catch (error) {}
    if (!message || message.error) {
      var detail = message && message.error ? String(message.error.message || "mutation failed")
        : "Herdr returned an invalid layout mutation response"
      mutationFailed(detail)
    }
    mutationWanted = false
    mutationId = ""
    mutationAgain.restart()
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
    if (!protocolSupported(protocol)) {
      state = "incompatible"
      errorMessage = "Herdr protocol " + protocol + " is not supported (expected 20 or 22)"
      eventWanted = false
      return
    }

    workspaces = Array.isArray(snapshot.workspaces) ? snapshot.workspaces : []
    tabs = Array.isArray(snapshot.tabs) ? snapshot.tabs : []
    panes = Array.isArray(snapshot.panes) ? snapshot.panes : []
    agents = Array.isArray(snapshot.agents) ? snapshot.agents : []
    layouts = Array.isArray(snapshot.layouts) ? snapshot.layouts : []
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
    id: mutationAgain
    interval: 0
    repeat: false
    onTriggered: root.startNextMutation()
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
    id: mutationSocket
    path: root.socketPath
    connected: root.running && root.mutationWanted

    onConnectionStateChanged: if (connected && root.mutationQueue.length > 0) {
      var next = root.mutationQueue.slice()
      var request = next.shift()
      root.mutationQueue = next
      root.mutationId = String(request.id || "")
      write(JSON.stringify(request) + "\n")
      flush()
    }
    onError: function(error) {
      root.mutationFailed("Cannot write Herdr layout at " + root.socketPath)
      root.mutationWanted = false
      root.mutationId = ""
      mutationAgain.restart()
    }

    parser: SplitParser {
      splitMarker: "\n"
      onRead: function(line) { root.handleMutationLine(line) }
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
