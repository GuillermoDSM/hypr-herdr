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
  property string selectedSpaceId: ""
  property string lastSpaceId: ""

  readonly property string pluginId: manifest && manifest.id ? String(manifest.id) : "guillermodsm.hypr-herdr"
  readonly property string focusedWorkspaceName: Hyprland.focusedWorkspace ? String(Hyprland.focusedWorkspace.name || "") : ""
  readonly property bool onHerdrWorkspace: spaceIdForWorkspace(focusedWorkspaceName) !== ""
  readonly property var selectedSpace: spaceById(selectedSpaceId)
  readonly property color foreground: Color.popups.text
  readonly property color dim: Color.muted

  function open(payloadJson) {
    opened = true
    var payload = null
    try { payload = JSON.parse(String(payloadJson || "{}")) } catch (error) {}
    if (payload && payload.spaceId) openSpace(String(payload.spaceId))
  }

  function close() {
    opened = false
  }

  function spaceById(id) {
    for (var i = 0; i < client.workspaces.length; i++) {
      if (String(client.workspaces[i].workspace_id || "") === String(id || "")) return client.workspaces[i]
    }
    return null
  }

  function workspaceByName(name) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (String(values[i].name || "") === String(name || "")) return values[i]
    }
    return null
  }

  function spaceIdForWorkspace(name) {
    for (var i = 0; i < client.workspaces.length; i++) {
      var id = String(client.workspaces[i].workspace_id || "")
      if (IdCodec.workspaceName(id) === String(name || "")) return id
    }
    return ""
  }

  function activateWorkspace(name) {
    var workspace = workspaceByName(name)
    if (workspace) {
      workspace.activate()
      return
    }
    if (Hyprland.usingLua)
      Hyprland.dispatch("hl.dsp.focus({ workspace = \"name:" + name + "\" })")
    else
      Hyprland.dispatch("workspace name:" + name)
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
    case "idle": return Color.muted
    default: return Qt.rgba(dim.r, dim.g, dim.b, 0.55)
    }
  }

  function openSpace(id) {
    var value = String(id || "")
    if (!spaceById(value)) return "unknown space: " + value
    selectedSpaceId = value
    lastSpaceId = value
    activateWorkspace(IdCodec.workspaceName(value))
    return "ok"
  }

  function openLast() {
    opened = true
    var target = lastSpaceId
    if (!spaceById(target)) target = client.focusedWorkspaceId
    if (!spaceById(target) && client.workspaces.length > 0)
      target = String(client.workspaces[0].workspace_id || "")
    return target === "" ? "no Herdr spaces" : openSpace(target)
  }

  function focusPane(id) {
    var appId = IdCodec.appId(id)
    var values = Hyprland.toplevels.values
    for (var i = 0; i < values.length; i++) {
      var top = values[i]
      var ipc = top.lastIpcObject || {}
      if (String(ipc.class || ipc.initialClass || "") === appId) {
        if (top.wayland) {
          top.wayland.activate()
        } else {
          if (top.workspace) top.workspace.activate()
          var address = String(top.address || "")
          if (Hyprland.usingLua)
            Hyprland.dispatch("hl.dsp.focus({ window = \"address:" + address + "\" })")
          else
            Hyprland.dispatch("focuswindow address:" + address)
        }
        return "ok"
      }
    }
    return "pane window is not attached"
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
      selectedSpaceId: selectedSpaceId,
      focusedWorkspace: focusedWorkspaceName,
      lastSnapshotAt: client.lastSnapshotAt
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
      if (!root.spaceById(root.selectedSpaceId)) {
        root.selectedSpaceId = root.spaceById(focusedWorkspaceId)
          ? focusedWorkspaceId
          : (workspaces.length > 0 ? String(workspaces[0].workspace_id || "") : "")
      }
      root.syncFocusedWorkspace()
    }
  }

  IpcHandler {
    target: root.pluginId

    function open(): string { return root.openLast() }
    function openLast(): string { return root.openLast() }
    function openSpace(id: string): string { return root.openSpace(id) }
    function focusPane(id: string): string { return root.focusPane(id) }
    function status(): string { return root.statusJson() }
    function reconcile(): string { client.requestSnapshot(); return "requested" }
    function close(): void { root.close() }
    function show(): void { root.opened = true }
  }

  PanelWindow {
    id: sidebar
    visible: root.opened && root.onHerdrWorkspace
    anchors { top: true; bottom: true; left: true }
    implicitWidth: Style.space(336)
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

    Column {
      anchors.fill: parent
      anchors.margins: Style.space(16)
      spacing: Style.space(14)

      Item {
        width: parent.width
        height: Math.max(titleColumn.implicitHeight, connectionDot.height)

        Column {
          id: titleColumn
          anchors.left: parent.left
          anchors.right: connectionDot.left
          anchors.rightMargin: Style.space(12)
          spacing: Style.space(2)

          Text {
            text: "HERDR"
            color: root.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.heading
            font.bold: true
            font.letterSpacing: 2
          }

          Text {
            width: parent.width
            text: client.state === "ready"
              ? client.workspaces.length + " spaces · " + client.panes.length + " panes"
              : client.state
            color: root.dim
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }

        Rectangle {
          id: connectionDot
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.topMargin: Style.space(7)
          width: Style.space(8)
          height: width
          radius: width / 2
          color: client.state === "ready" ? Color.accent : Color.urgent
        }
      }

      Text {
        visible: client.errorMessage !== ""
        width: parent.width
        text: client.errorMessage
        color: Color.urgent
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }

      Flickable {
        width: parent.width
        height: Math.min(spacesColumn.implicitHeight, Style.space(176))
        contentWidth: width
        contentHeight: spacesColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: spacesColumn
          width: parent.width
          spacing: Style.space(4)

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
              onClicked: root.openSpace(String(modelData.workspace_id || ""))
            }
          }
        }
      }

      Rectangle {
        width: parent.width
        height: 1
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.16)
      }

      Flickable {
        width: parent.width
        height: Math.max(0, sidebar.height - y - Style.space(16))
        contentWidth: width
        contentHeight: detailColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: detailColumn
          width: parent.width
          spacing: Style.space(14)

          Repeater {
            model: root.tabsFor(root.selectedSpaceId)

            Column {
              id: tabSection
              required property var modelData
              readonly property string tabId: String(modelData.tab_id || "")
              width: detailColumn.width
              spacing: Style.space(6)

              Text {
                width: parent.width
                text: String(tabSection.modelData.label || ("Tab " + tabSection.modelData.number)).toUpperCase()
                color: root.dim
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1
                elide: Text.ElideRight
              }

              Repeater {
                model: root.panesFor(tabSection.tabId)

                Button {
                  required property var modelData
                  width: tabSection.width
                  leftAlign: true
                  text: root.displayTitle(modelData)
                  iconText: "●"
                  foreground: root.statusColor(modelData.agent_status)
                  iconSize: Style.font.caption
                  selected: String(modelData.pane_id || "") === client.focusedPaneId
                  tooltipText: String(modelData.cwd || "")
                  onClicked: root.focusPane(String(modelData.pane_id || ""))
                }
              }
            }
          }

          Text {
            visible: client.state === "ready" && root.selectedSpace && root.tabsFor(root.selectedSpaceId).length === 0
            width: parent.width
            text: "This space has no tabs yet."
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
