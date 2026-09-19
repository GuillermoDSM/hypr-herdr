import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "IdCodec.js" as IdCodec

Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: true
  property bool preparationEnabled: true
  property string selectedSpaceId: ""
  property string lastSpaceId: ""
  property real sidebarWidthRatio: 0.22
  property bool settingsLoaded: false
  property bool emptyEntryRequested: false
  property bool creatingSpace: false
  property string pendingCreatedSpaceId: ""
  property bool creationOpenRequested: false
  property var creationWorkspaceIds: []
  property string createSpaceError: ""

  readonly property string pluginId: manifest && manifest.id ? String(manifest.id) : "guillermodsm.hypr-herdr"
  readonly property string focusedWorkspaceName: Hyprland.focusedWorkspace
    ? String((Hyprland.focusedWorkspace.lastIpcObject || {}).name || Hyprland.focusedWorkspace.name || "")
    : ""
  readonly property bool onHerdrWorkspace: spaceIdForWorkspace(focusedWorkspaceName) !== ""
  readonly property bool emptyEntryVisible: emptyEntryRequested
    && client.state === "ready" && client.workspaces.length === 0
  readonly property var selectedSpace: spaceById(selectedSpaceId)
  readonly property color foreground: Color.popups.text
  readonly property color dim: Util.alpha(Color.popups.text, 0.65)
  readonly property string settingsPath: Quickshell.statePath("hypr-herdr-panel.json")
  readonly property real minimumSidebarWidth: Style.space(160)
  readonly property real maximumSidebarWidth: Style.space(620)
  readonly property real sidebarPixelWidth: {
    var screenWidth = sidebar.screen ? Number(sidebar.screen.width || 0) : 0
    if (screenWidth <= 0) return Style.space(336)
    return Math.round(Math.max(minimumSidebarWidth,
                              Math.min(maximumSidebarWidth, screenWidth * sidebarWidthRatio)))
  }

  function open(payloadJson) {
    opened = true
    if (client.workspaces.length === 0) emptyEntryRequested = true
    var payload = null
    try { payload = JSON.parse(String(payloadJson || "{}")) } catch (error) {}
    if (payload && payload.spaceId) openSpace(String(payload.spaceId))
  }

  function close() {
    opened = false
  }

  function requestClose() {
    if (shell && typeof shell.hide === "function") shell.hide(pluginId)
    else close()
  }

  function spaceById(id) {
    for (var i = 0; i < client.workspaces.length; i++) {
      if (String(client.workspaces[i].workspace_id || "") === String(id || "")) return client.workspaces[i]
    }
    return null
  }

  function spaceIdForWorkspace(name) {
    var leasedId = lease.spaceIdForName(name)
    if (leasedId !== "") return leasedId
    for (var i = 0; i < client.workspaces.length; i++) {
      var id = String(client.workspaces[i].workspace_id || "")
      if (IdCodec.workspaceName(id) === String(name || "")) return id
    }
    return ""
  }

  function tabsFor(spaceId) {
    var result = []
    for (var i = 0; i < client.tabs.length; i++) {
      if (String(client.tabs[i].workspace_id || "") === String(spaceId || "")) result.push(client.tabs[i])
    }
    result.sort(function(a, b) { return Number(a.number || 0) - Number(b.number || 0) })
    return result
  }

  function panesFor(tabId) {
    var result = []
    for (var i = 0; i < client.panes.length; i++) {
      if (String(client.panes[i].tab_id || "") === String(tabId || "")) result.push(client.panes[i])
    }
    return result
  }

  function tabById(id) {
    for (var i = 0; i < client.tabs.length; i++) {
      if (String(client.tabs[i].tab_id || "") === String(id || "")) return client.tabs[i]
    }
    return null
  }

  function agentName(agent) {
    var name = String((agent && (agent.display_agent || agent.agent_name || agent.agent)) || "")
    return name !== "" ? name : "Agent"
  }

  function agentLocation(agent) {
    var workspace = spaceById(agent && agent.workspace_id)
    var workspaceLabel = String((workspace && (workspace.label || workspace.workspace_id))
                                || (agent && agent.workspace_id) || "Space")
    var tab = tabById(agent && agent.tab_id)
    if (!tab || tabsFor(agent.workspace_id).length < 2) return workspaceLabel
    return workspaceLabel + " · " + String(tab.label || ("Tab " + tab.number))
  }

  function statusSymbol(status) {
    switch (String(status || "unknown")) {
    case "working": return "●"
    case "blocked": return "×"
    case "done": return "✓"
    case "idle": return "○"
    default: return "·"
    }
  }

  function statusRank(status) {
    switch (String(status || "unknown")) {
    case "blocked": return 0
    case "done": return 1
    case "working": return 2
    case "idle": return 3
    default: return 4
    }
  }

  function sortedAgents() {
    var result = client.agents.slice()
    result.sort(function(a, b) {
      var rank = statusRank(a.agent_status) - statusRank(b.agent_status)
      if (rank !== 0) return rank
      var sequence = Number(b.state_change_seq || 0) - Number(a.state_change_seq || 0)
      if (sequence !== 0) return sequence
      return agentName(a).localeCompare(agentName(b))
    })
    return result
  }

  function displayTitle(pane) {
    var title = String((pane && (pane.terminal_title_stripped || pane.terminal_title)) || "")
    if (title !== "") return title
    var agent = String((pane && pane.agent) || "")
    return agent !== "" ? agent : "Terminal"
  }

  function statusColor(status) {
    switch (String(status || "unknown")) {
    case "working": return Color.accent
    case "blocked": return Color.urgent
    case "done": return foreground
    case "idle": return dim
    default: return Util.alpha(foreground, 0.5)
    }
  }

  function setSidebarWidth(width) {
    var screenWidth = sidebar.screen ? Number(sidebar.screen.width || 0) : 0
    if (screenWidth <= 0) return
    var clamped = Math.max(minimumSidebarWidth, Math.min(maximumSidebarWidth, Number(width || 0)))
    sidebarWidthRatio = clamped / screenWidth
  }

  function loadSettings(raw) {
    if (settingsLoaded) return
    try {
      var parsed = JSON.parse(String(raw || "{}"))
      var ratio = Number(parsed.sidebarWidthRatio)
      if (isFinite(ratio) && ratio > 0) sidebarWidthRatio = Math.max(0.04, Math.min(0.9, ratio))
    } catch (error) {
      console.warn("hypr-herdr: could not parse panel settings:", error)
    }
    settingsLoaded = true
  }

  function saveSettings() {
    if (!settingsLoaded) return
    settingsFile.setText(JSON.stringify({ version: 1, sidebarWidthRatio: sidebarWidthRatio }, null, 2) + "\n")
  }

  function openSpace(id) {
    var value = String(id || "")
    if (!spaceById(value)) return "unknown space: " + value
    opened = true
    emptyEntryRequested = false
    selectedSpaceId = value
    lastSpaceId = value
    if (!workspaceManager.spaceReady(value)) return workspaceManager.prepareSpace(value)
    return lease.openSpace(value)
  }

  function openLast() {
    opened = true
    var target = lastSpaceId
    if (!spaceById(target)) target = client.focusedWorkspaceId
    if (!spaceById(target) && client.workspaces.length > 0)
      target = String(client.workspaces[0].workspace_id || "")
    if (target === "") {
      emptyEntryRequested = true
      return "no Herdr spaces"
    }
    emptyEntryRequested = false
    if (!workspaceManager.spaceReady(target)) return workspaceManager.prepareSpace(target)
    return lease.toggle(target)
  }

  function currentCwd() {
    var preferredSpaceId = selectedSpaceId !== "" ? selectedSpaceId : client.focusedWorkspaceId
    for (var i = 0; i < client.panes.length; i++) {
      var focusedPane = client.panes[i]
      if (String(focusedPane.pane_id || "") === client.focusedPaneId) {
        var focusedCwd = String(focusedPane.cwd || focusedPane.foreground_cwd || "")
        if (focusedCwd !== "") return focusedCwd
        break
      }
    }

    for (var i = 0; i < client.panes.length; i++) {
      var pane = client.panes[i]
      var paneCwd = String(pane.cwd || pane.foreground_cwd || "")
      if (paneCwd === "") continue
      if (String(pane.workspace_id || "") === preferredSpaceId) return paneCwd
    }
    return Quickshell.env("HOME") || "/"
  }

  function workspaceIds() {
    var result = []
    for (var i = 0; i < client.workspaces.length; i++) {
      var id = String(client.workspaces[i].workspace_id || "")
      if (id !== "") result.push(id)
    }
    return result
  }

  function createSpace() {
    if (creatingSpace) return "workspace creation already in progress"
    if (client.state !== "ready") return "Herdr is not ready"
    if (lease.busy) return "workspace transaction already in progress"
    if (lease.recoveryRequired) return "workspace recovery required"

    creatingSpace = true
    pendingCreatedSpaceId = ""
    creationOpenRequested = false
    creationWorkspaceIds = workspaceIds()
    createSpaceError = ""
    opened = true

    var result = client.createWorkspace(currentCwd())
    if (result !== "requested") {
      failCreateSpace(result)
      return result
    }
    return result
  }

  function failCreateSpace(message) {
    creatingSpace = false
    pendingCreatedSpaceId = ""
    creationOpenRequested = false
    creationWorkspaceIds = []
    createSpaceError = String(message || "workspace creation failed")
    return createSpaceError
  }

  function finishCreateSpace() {
    creatingSpace = false
    pendingCreatedSpaceId = ""
    creationOpenRequested = false
    creationWorkspaceIds = []
    createSpaceError = ""
    emptyEntryRequested = false
  }

  function handleWorkspaceCreated(id) {
    if (!creatingSpace) return
    pendingCreatedSpaceId = String(id || "")
    client.requestSnapshot()
  }

  function handleCreateSnapshot() {
    if (!creatingSpace) return

    var createdId = pendingCreatedSpaceId
    if (createdId === "") {
      var knownIds = creationWorkspaceIds
      for (var i = 0; i < client.workspaces.length; i++) {
        var candidate = String(client.workspaces[i].workspace_id || "")
        if (candidate !== "" && knownIds.indexOf(candidate) === -1) {
          createdId = candidate
          break
        }
      }
      if (createdId !== "") pendingCreatedSpaceId = createdId
    }

    if (createdId === "") {
      client.requestSnapshot()
      return
    }
    if (!spaceById(createdId)) {
      client.requestSnapshot()
      return
    }

    selectedSpaceId = createdId
    lastSpaceId = createdId
    emptyEntryRequested = false
    workspaceManager.prepareSpace(createdId)
    maybeOpenCreatedSpace()
  }

  function maybeOpenCreatedSpace() {
    if (!creatingSpace || pendingCreatedSpaceId === "" || creationOpenRequested) return
    if (workspaceManager.state === "error") {
      failCreateSpace(workspaceManager.errorMessage || "workspace preparation failed")
      return
    }
    if (!workspaceManager.spaceReady(pendingCreatedSpaceId)) {
      workspaceManager.prepareSpace(pendingCreatedSpaceId)
      return
    }

    creationOpenRequested = true
    var result = lease.openSpace(pendingCreatedSpaceId)
    if (result === "preparing") {
      creationOpenRequested = false
      workspaceManager.prepareSpace(pendingCreatedSpaceId)
    } else if (result !== "requested") {
      failCreateSpace(result)
    }
  }

  function releaseLease() {
    return lease.release()
  }

  function focusPane(id) {
    return workspaceManager.focusPane(String(id || ""))
  }

  function statusJson() {
    return JSON.stringify({
      state: client.state,
      error: client.errorMessage,
      socket: client.socketPath,
      version: client.serverVersion,
      protocol: client.protocol,
      workspaces: client.workspaces.length,
      tabs: client.tabs.length,
      panes: client.panes.length,
      agents: client.agents.length,
      layouts: client.layouts.length,
      selectedSpaceId: selectedSpaceId,
      focusedWorkspace: focusedWorkspaceName,
      lastSnapshotAt: client.lastSnapshotAt,
      panel: {
        opened: opened,
        visible: sidebar.visible,
        onHerdrWorkspace: onHerdrWorkspace,
        width: sidebarPixelWidth,
        widthRatio: sidebarWidthRatio,
        minWidth: minimumSidebarWidth,
        maxWidth: maximumSidebarWidth,
        screenWidth: sidebar.screen ? Number(sidebar.screen.width || 0) : 0
      },
      preparation: {
        state: workspaceManager.state,
        error: workspaceManager.errorMessage,
        attachedPanes: workspaceManager.attachedPaneCount,
        unavailablePanes: workspaceManager.unavailablePaneCount,
        pendingPaneId: workspaceManager.pendingPaneId
      },
      creation: {
        pending: creatingSpace,
        spaceId: pendingCreatedSpaceId,
        error: createSpaceError
      },
      layout: {
        state: workspaceManager.layoutState,
        error: workspaceManager.layoutErrorMessage,
        pendingSpaceId: workspaceManager.pendingLayoutSpaceId
      },
      lease: {
        active: lease.active,
        busy: lease.busy,
        recoveryRequired: lease.recoveryRequired,
        phase: lease.phase,
        error: lease.errorMessage,
        slot: lease.slotId,
        ownerSpaceId: lease.ownerSpaceId,
        home: lease.homeId,
        parking: lease.parkingId
      }
    })
  }

  onFocusedWorkspaceNameChanged: syncFocusedWorkspace()

  function syncFocusedWorkspace() {
    var id = spaceIdForWorkspace(focusedWorkspaceName)
    if (id === "") return
    selectedSpaceId = id
    lastSpaceId = id
  }

  HerdrClient {
    id: client
    onSnapshotApplied: {
      lease.reconcile()
      if (!root.spaceById(root.selectedSpaceId)) {
        root.selectedSpaceId = root.spaceById(focusedWorkspaceId)
          ? focusedWorkspaceId
          : (workspaces.length > 0 ? String(workspaces[0].workspace_id || "") : "")
      }
      root.syncFocusedWorkspace()
      root.handleCreateSnapshot()
    }
    onWorkspaceCreated: function(workspaceId) { root.handleWorkspaceCreated(workspaceId) }
    onWorkspaceCreateFailed: function(message) { root.failCreateSpace(message) }
  }

  FileView {
    id: settingsFile
    path: root.settingsPath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadSettings(text())
    onLoadFailed: root.loadSettings("")
  }

  WorkspaceLease {
    id: lease
    onOperationFinished: function(operation, success, message) {
      if (root.creatingSpace && root.creationOpenRequested && operation !== "release") {
        if (!success) {
          root.failCreateSpace(message)
          return
        }
        root.finishCreateSpace()
      }
      if (!success) return
      if (operation !== "release") {
        root.selectedSpaceId = ownerSpaceId
        root.lastSpaceId = ownerSpaceId
      }
    }
  }

  WorkspaceManager {
    id: workspaceManager
    enabled: root.preparationEnabled && client.state === "ready"
    persistenceKey: root.pluginId
    spaces: client.workspaces
    panes: client.panes
    layouts: client.layouts
    layoutSyncEnabled: true
    layoutWriteBusy: client.mutationWanted || client.mutationQueue.length > 0
    leaseCoordinator: lease
    onLayoutRatioUpdates: function(updates) { client.setLayoutRatios(updates) }
    onReconciliationComplete: root.maybeOpenCreatedSpace()
    onStateChanged: {
      if (root.creatingSpace && state === "error")
        root.failCreateSpace(errorMessage || "workspace preparation failed")
      else
        root.maybeOpenCreatedSpace()
    }
  }

  IpcHandler {
    target: root.pluginId

    function open(): string { return root.openLast() }
    function openLast(): string { return root.openLast() }
    function openSpace(id: string): string { return root.openSpace(id) }
    function focusPane(id: string): string { return root.focusPane(id) }
    function release(): string { return root.releaseLease() }
    function status(): string { return root.statusJson() }
    function reconcile(): string { client.requestSnapshot(); return "requested" }
    function close(): void { root.requestClose() }
    function show(): void {
      root.opened = true
      if (client.state === "ready" && client.workspaces.length === 0)
        root.emptyEntryRequested = true
    }
  }

  PanelWindow {
    id: sidebar
    visible: root.opened && (root.onHerdrWorkspace || root.emptyEntryVisible || root.creatingSpace)
    anchors { top: true; bottom: true; left: true }
    // At fractional scales (e.g. 1.25) the bar/sidebar boundary lands on a half
    // device pixel, so rounding can leave a 1px seam exposing the wallpaper
    // between them. Overlapping one unit hides it under our opaque background;
    // at integer scales the overlap only covers the bar's background-colored
    // edge, which has no widgets.
    margins.top: -1
    margins.bottom: -1
    implicitWidth: root.sidebarPixelWidth
    color: Color.popups.background
    exclusionMode: ExclusionMode.Auto
    WlrLayershell.namespace: "hypr-herdr-sidebar"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Rectangle {
      anchors.right: parent.right
      width: Math.max(1, Style.normalBorderWidth)
      height: parent.height
      color: Color.popups.border
    }

    MouseArea {
      id: resizeHandle
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.right: parent.right
      width: Style.space(12)
      z: 10
      hoverEnabled: true
      cursorShape: Qt.SizeHorCursor
      acceptedButtons: Qt.LeftButton
      preventStealing: true
      property real pressGlobalX: 0
      property real pressWidth: 0

      onPressed: function(mouse) {
        var point = resizeHandle.mapToGlobal(mouse.x, mouse.y)
        pressGlobalX = point.x
        pressWidth = sidebar.width
      }
      onPositionChanged: function(mouse) {
        if (!pressed) return
        var point = resizeHandle.mapToGlobal(mouse.x, mouse.y)
        root.setSidebarWidth(pressWidth + point.x - pressGlobalX)
      }
      onReleased: root.saveSettings()
      onCanceled: root.saveSettings()
    }

    Column {
      anchors.fill: parent
      anchors.topMargin: Style.space(16)
      anchors.bottomMargin: Style.space(16)
      anchors.leftMargin: Style.space(16)
      anchors.rightMargin: Style.space(20)
      spacing: Style.space(10)
      Text {
        id: sidebarError
        visible: client.errorMessage !== "" || root.createSpaceError !== ""
        width: parent.width
        height: visible ? implicitHeight : 0
        text: client.errorMessage !== "" ? client.errorMessage : root.createSpaceError
        color: Color.urgent
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }

      Item {
        id: sections
        width: parent.width
        height: Math.max(0, parent.height - y)

        Item {
          id: spacesSection
          width: parent.width
          height: Math.max(0, Math.floor((sections.height - Style.space(1)) / 2))

          Column {
            anchors.fill: parent
            spacing: Style.space(4)

            Text {
              id: spacesHeading
              width: parent.width
              text: "SPACES"
              color: root.dim
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1
            }

            Flickable {
              width: parent.width
              height: Math.max(0, spacesSection.height - spacesHeading.implicitHeight
                - newSpaceButton.implicitHeight - Style.space(8))
              contentWidth: width
              contentHeight: spacesColumn.implicitHeight
              clip: true
              boundsBehavior: Flickable.StopAtBounds

              Column {
                id: spacesColumn
                width: parent.width
                spacing: Style.space(2)

                Repeater {
                  model: client.workspaces

                  Button {
                    required property var modelData
                    width: spacesColumn.width
                    text: String(modelData.label || modelData.workspace_id || "Space")
                    iconText: modelData.focused ? "●" : ""
                    leftAlign: true
                    selected: String(modelData.workspace_id || "") === root.selectedSpaceId
                    foreground: root.foreground
                    fontSize: Style.font.bodySmall
                    iconSize: Style.font.caption
                    verticalPadding: Style.space(3)
                    onClicked: root.openSpace(String(modelData.workspace_id || ""))
                  }
                }

                Text {
                  visible: client.state === "ready" && client.workspaces.length === 0
                  width: parent.width
                  text: "No spaces yet."
                  color: root.dim
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                }
              }
            }

            Button {
              id: newSpaceButton
              width: parent.width
              text: root.creatingSpace ? "creating..." : "new"
              leftAlign: true
              foreground: root.foreground
              fontSize: Style.font.bodySmall
              verticalPadding: Style.space(3)
              enabled: !root.creatingSpace && client.state === "ready"
                && !lease.busy && !lease.recoveryRequired
              onClicked: root.createSpace()
            }
          }
        }

        Rectangle {
          id: sectionsDivider
          anchors.top: spacesSection.bottom
          width: parent.width
          height: 1
          color: Util.alpha(root.foreground, 0.16)
        }

        Item {
          id: agentsSection
          anchors.top: sectionsDivider.bottom
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom

          Column {
            anchors.fill: parent
            spacing: Style.space(4)

            Item {
              id: agentsHeader
              width: parent.width
              height: agentsHeading.implicitHeight

              Text {
                id: agentsHeading
                anchors.left: parent.left
                text: "AGENTS"
                color: root.dim
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1
              }

              Text {
                anchors.right: parent.right
                anchors.baseline: agentsHeading.baseline
                text: String(client.agents.length)
                color: root.dim
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }
            }

            Flickable {
              width: parent.width
              height: Math.max(0, agentsSection.height - agentsHeader.height - Style.space(4))
              contentWidth: width
              contentHeight: agentsColumn.implicitHeight
              clip: true
              boundsBehavior: Flickable.StopAtBounds

              Column {
                id: agentsColumn
                width: parent.width
                spacing: Style.space(2)

                Repeater {
                  model: root.sortedAgents()

                  Rectangle {
                    id: agentRow
                    required property var modelData
                    readonly property bool selected: String(modelData.pane_id || "") === client.focusedPaneId
                    width: agentsColumn.width
                    height: Style.space(36)
                    radius: Style.cornerRadius
                    color: selected || agentMouse.containsMouse
                      ? Style.selectedFillFor(root.foreground, Color.accent)
                      : "transparent"

                    Text {
                      id: agentStatus
                      anchors.left: parent.left
                      anchors.leftMargin: Style.space(8)
                      anchors.top: parent.top
                      anchors.topMargin: Style.space(5)
                      text: root.statusSymbol(agentRow.modelData.agent_status)
                      color: root.statusColor(agentRow.modelData.agent_status)
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption
                    }

                    Column {
                      anchors.left: agentStatus.right
                      anchors.leftMargin: Style.space(6)
                      anchors.right: parent.right
                      anchors.rightMargin: Style.space(8)
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: 0

                      Text {
                        width: parent.width
                        text: root.agentLocation(agentRow.modelData)
                        color: root.foreground
                        font.family: Style.font.family
                        font.pixelSize: Style.font.bodySmall
                        font.bold: true
                        elide: Text.ElideRight
                      }

                      Text {
                        width: parent.width
                        text: root.agentName(agentRow.modelData)
                        color: root.dim
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideRight
                      }
                    }

                    MouseArea {
                      id: agentMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      enabled: String(agentRow.modelData.terminal_id || "") !== ""
                      onClicked: root.focusPane(String(agentRow.modelData.pane_id || ""))
                    }
                  }
                }

                Text {
                  visible: client.state === "ready" && client.agents.length === 0
                  width: parent.width
                  text: "No agents are running."
                  color: root.dim
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  wrapMode: Text.WordWrap
                }
              }
            }
          }
        }
      }
    }
  }

  Component.onCompleted: settingsFile.reload()
}
