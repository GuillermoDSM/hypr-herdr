import QtQuick
import Quickshell
import Quickshell.Hyprland
import "IdCodec.js" as IdCodec
import "LeaseCodec.js" as LeaseCodec

Item {
  id: root
  visible: false

  property var spaces: []
  property var panes: []
  property var leaseCoordinator: null
  property bool enabled: false
  property string testLauncher: ""
  property int testHomeBase: 0
  property string prioritySpaceId: ""
  property string pendingPaneId: ""
  property string pendingAppId: ""
  property string pendingCommand: ""
  property string pendingSpaceId: ""
  property int pendingHomeId: 0
  property var managedAppIds: ({})
  property var attachedTerminalIds: ({})
  property var reattachingTerminalIds: ({})
  property var failedTerminalIds: ({})
  property string state: enabled ? "preparing" : "disabled"
  property string errorMessage: ""
  property int attachedPaneCount: 0
  property int unavailablePaneCount: 0
  property int settleAttempts: 0
  property string settlingKey: ""
  property bool inventoryReady: false

  readonly property bool preparing: enabled && state === "preparing"
  readonly property bool ready: enabled && state === "ready"

  signal reconciliationComplete()

  function decodeToken(value) {
    try {
      var decoded = IdCodec.decode(value)
      return IdCodec.encode(decoded) === value ? decoded : ""
    } catch (error) {
      return ""
    }
  }

  function workspaceId(workspace) {
    var ipc = workspace ? (workspace.lastIpcObject || {}) : {}
    return Number(ipc.id !== undefined ? ipc.id : (workspace ? workspace.id : 0))
  }

  function workspaceName(workspace) {
    var ipc = workspace ? (workspace.lastIpcObject || {}) : {}
    return String(ipc.name !== undefined ? ipc.name : (workspace ? workspace.name || "" : ""))
  }

  function workspaceWindowCount(workspace) {
    var ipc = workspace ? (workspace.lastIpcObject || {}) : {}
    if (ipc.windows !== undefined) return Number(ipc.windows)
    return workspace && workspace.toplevels ? workspace.toplevels.values.length : 0
  }

  function workspaceValues() {
    var source = Hyprland.workspaces.values || []
    var result = []
    var indexes = {}
    for (var i = 0; i < source.length; i++) {
      var key = String(workspaceId(source[i]))
      if (indexes[key] === undefined) {
        indexes[key] = result.length
        result.push(source[i])
      } else {
        var index = indexes[key]
        if (workspaceSnapshotScore(source[i]) > workspaceSnapshotScore(result[index]))
          result[index] = source[i]
      }
    }
    return result
  }

  function workspaceSnapshotScore(workspace) {
    var ipc = workspace ? (workspace.lastIpcObject || {}) : {}
    var score = 0
    if (ipc.id !== undefined && Number(workspace.id) === Number(ipc.id)) score++
    if (ipc.name !== undefined && String(workspace.name || "") === String(ipc.name)) score++
    return score
  }

  function workspaceById(id) {
    var values = workspaceValues()
    for (var i = 0; i < values.length; i++)
      if (workspaceId(values[i]) === Number(id)) return values[i]
    return null
  }

  function workspaceByName(name) {
    var values = workspaceValues()
    for (var i = 0; i < values.length; i++)
      if (workspaceName(values[i]) === String(name)) return values[i]
    return null
  }

  function spaceForId(spaceId) {
    for (var i = 0; i < spaces.length; i++)
      if (String(spaces[i].workspace_id || "") === String(spaceId)) return spaces[i]
    return null
  }

  function panesForSpace(spaceId) {
    var result = []
    for (var i = 0; i < panes.length; i++)
      if (String(panes[i].workspace_id || "") === String(spaceId)) result.push(panes[i])
    return result
  }

  function stableWorkspace(spaceId) {
    var values = workspaceValues()
    for (var i = 0; i < values.length; i++) {
      var parsed = LeaseCodec.parseHerdr(workspaceName(values[i]))
      var expectedId = parsed ? (parsed.leased ? parsed.slotId : parsed.homeId) : 0
      if (parsed && workspaceId(values[i]) === expectedId
          && decodeToken(parsed.encodedSpaceId) === String(spaceId))
        return { workspace: values[i], parsed: parsed }
    }
    return null
  }

  function topClass(top) {
    var ipc = top ? (top.lastIpcObject || {}) : {}
    return String(ipc.class || ipc.initialClass || "")
  }

  function topAddress(top) {
    var ipc = top ? (top.lastIpcObject || {}) : {}
    return String(ipc.address || (top ? top.address || "" : ""))
  }

  function topWorkspaceId(top) {
    var ipc = top ? (top.lastIpcObject || {}) : {}
    if (ipc.workspace && ipc.workspace.id !== undefined) return Number(ipc.workspace.id)
    return top && top.workspace ? workspaceId(top.workspace) : 0
  }

  function topsForAppId(appId) {
    var result = []
    var values = Hyprland.toplevels.values || []
    var addresses = {}
    for (var i = 0; i < values.length; i++) {
      var address = topAddress(values[i])
      if (topClass(values[i]) === appId && address !== "" && !addresses[address]) {
        addresses[address] = true
        result.push(values[i])
      }
    }
    return result
  }

  function assignedHomes() {
    var result = {}
    var used = {}
    var values = workspaceValues()
    for (var i = 0; i < values.length; i++) used[workspaceId(values[i])] = true

    var ordered = spaces.slice().sort(function(a, b) {
      return String(a.workspace_id || "").localeCompare(String(b.workspace_id || ""))
    })
    for (var index = 0; index < ordered.length; index++) {
      var spaceId = String(ordered[index].workspace_id || "")
      if (spaceId === "") continue
      var existing = stableWorkspace(spaceId)
      if (existing) {
        result[spaceId] = existing.parsed.homeId
        used[existing.parsed.homeId] = true
        continue
      }
      if (pendingSpaceId === spaceId && pendingHomeId > 10) {
        result[spaceId] = pendingHomeId
        used[pendingHomeId] = true
        continue
      }
      var legacy = workspaceByName(IdCodec.workspaceName(spaceId))
      if (legacy && workspaceId(legacy) > 10 && workspaceWindowCount(legacy) > 0) {
        result[spaceId] = workspaceId(legacy)
        used[result[spaceId]] = true
        continue
      }

      for (var attempt = 0; attempt < 10000; attempt++) {
        var candidate = testHomeBase > 10
          ? testHomeBase + index + attempt * ordered.length
          : LeaseCodec.homeCandidate(spaceId, attempt)
        if (!used[candidate]) {
          result[spaceId] = candidate
          used[candidate] = true
          break
        }
      }
    }
    return result
  }

  function targetWorkspaceId(spaceId, homes) {
    var existing = stableWorkspace(spaceId)
    if (existing) return existing.parsed.leased ? existing.parsed.slotId : existing.parsed.homeId
    return Number(homes[spaceId] || 0)
  }

  function luaString(value) {
    return JSON.stringify(String(value))
  }

  function shellQuote(value) {
    return "'" + String(value).replace(/'/g, "'\\''") + "'"
  }

  function commandForPane(pane) {
    var paneId = String(pane.pane_id || "")
    var terminalId = String(pane.terminal_id || "")
    var appId = IdCodec.appId(paneId)
    var title = "Hypr Herdr · " + paneId
    var cwd = String(pane.cwd || Quickshell.env("HOME") || "/")
    if (testLauncher !== "")
      return [testLauncher, appId, title, cwd, terminalId].map(shellQuote).join(" ")
    return ["uwsm-app", "--", "xdg-terminal-exec", "--app-id=" + appId,
            "--title=" + title, "--dir=" + cwd, "--", "herdr", "terminal", "attach",
            terminalId, "--takeover"].map(shellQuote).join(" ")
  }

  function schedule() {
    if (enabled && inventoryReady) reconcileTimer.restart()
  }

  function beginSettling(key) {
    var value = String(key)
    if (settlingKey !== value) {
      settlingKey = value
      settleAttempts = 0
    }
    settleTimer.restart()
  }

  function markManaged(appId, managed) {
    var next = Object.assign({}, managedAppIds)
    if (managed) next[appId] = true
    else delete next[appId]
    managedAppIds = next
  }

  function rememberTerminal(appId, terminalId) {
    var next = Object.assign({}, attachedTerminalIds)
    if (terminalId === "") delete next[appId]
    else next[appId] = terminalId
    attachedTerminalIds = next
  }

  function setMapValue(propertyName, key, value) {
    var source = root[propertyName]
    var next = Object.assign({}, source)
    if (value === "") delete next[key]
    else next[key] = value
    root[propertyName] = next
  }

  function renameWorkspace(workspace, spaceId, homeId) {
    var currentId = workspaceId(workspace)
    var currentName = workspaceName(workspace)
    var stableName = LeaseCodec.stableName(homeId, IdCodec.encode(spaceId))
    var code = "function() local ws = hl.get_workspace(" + currentId + "); "
      + "if not ws or ws.name ~= " + luaString(currentName) + " then return end; "
      + (currentId === homeId ? "" : "if hl.get_workspace(" + homeId + ") then return end; ")
      + "hl.dispatch(hl.dsp.workspace.rename({ workspace = ws, name = " + luaString(stableName) + " })); "
      + (currentId === homeId ? "" : "hl.dispatch(hl.dsp.workspace.change_id({ workspace = ws, id = " + homeId + " })); ")
      + "end"
    Hyprland.dispatch(code)
    beginSettling("rename:" + currentId + ":" + stableName)
  }

  function launchPane(pane, targetId) {
    var paneId = String(pane.pane_id || "")
    var appId = IdCodec.appId(paneId)
    pendingPaneId = paneId
    pendingAppId = appId
    pendingCommand = commandForPane(pane)
    pendingSpaceId = String(pane.workspace_id || "")
    pendingHomeId = targetId
    markManaged(appId, true)
    var destination = stableWorkspace(String(pane.workspace_id || ""))
    var code = "function() "
      + "if hl.get_window(" + luaString("class:" + appId) + ") then return end; "
      + (destination
        ? "local destination = hl.get_workspace(" + targetId + "); if not destination or destination.name ~= " + luaString(workspaceName(destination.workspace)) + " then return end; "
        : "if hl.get_workspace(" + targetId + ") then return end; ")
      + "hl.dispatch(hl.dsp.exec_cmd(" + luaString(pendingCommand)
      + ", { workspace = " + luaString(String(targetId) + " silent")
      + ", no_initial_focus = true })) end"
    Hyprland.dispatch(code)
    beginSettling("launch:" + appId)
    launchTimeout.restart()
  }

  function moveTop(top, targetId, spaceId, appId) {
    var address = topAddress(top)
    if (address === "") return
    var destination = stableWorkspace(spaceId)
    if (!destination) {
      pendingSpaceId = String(spaceId)
      pendingHomeId = targetId
    }
    var code = "function() "
      + "local window = hl.get_window(" + luaString("address:" + address) + "); "
      + "if not window or window.class ~= " + luaString(appId) + " then return end; "
      + (destination
        ? "local destination = hl.get_workspace(" + targetId + "); if not destination or destination.name ~= " + luaString(workspaceName(destination.workspace)) + " then return end; "
        : "if hl.get_workspace(" + targetId + ") then return end; ")
      + "hl.dispatch(hl.dsp.window.move({ window = window, workspace = "
      + luaString(String(targetId)) + ", follow = false })) end"
    Hyprland.dispatch(code)
    beginSettling("move:" + address + ":" + targetId)
  }

  function closeTop(top, appId) {
    var address = topAddress(top)
    if (address !== "") {
      var code = "function() local window = hl.get_window(" + luaString("address:" + address) + "); "
        + "if not window or window.class ~= " + luaString(appId) + " then return end; "
        + "hl.dispatch(hl.dsp.window.close({ window = window })) end"
      Hyprland.dispatch(code)
    }
  }

  function reconcile() {
    if (!enabled) {
      state = "disabled"
      return
    }
    if (leaseCoordinator && (leaseCoordinator.busy || leaseCoordinator.recoveryRequired)) {
      state = "waiting"
      return
    }

    var homes = assignedHomes()
    var expected = {}
    var attached = 0
    var unavailable = 0
    errorMessage = ""

    for (var spaceIndex = 0; spaceIndex < spaces.length; spaceIndex++) {
      var spaceId = String(spaces[spaceIndex].workspace_id || "")
      if (spaceId === "") continue
      var stable = stableWorkspace(spaceId)
      var legacy = workspaceByName(IdCodec.workspaceName(spaceId))
      if (!stable && legacy && workspaceWindowCount(legacy) > 0) {
        var legacyHome = Number(homes[spaceId] || 0)
        if (!legacyHome || (workspaceById(legacyHome) && workspaceById(legacyHome) !== legacy)) {
          state = "error"
          errorMessage = "home workspace collision for " + spaceId
          return
        }
        renameWorkspace(legacy, spaceId, legacyHome)
        state = "preparing"
        return
      }
    }

    var orderedPanes = panes.slice().sort(function(a, b) {
      var aPriority = String(a.workspace_id || "") === prioritySpaceId ? 0 : 1
      var bPriority = String(b.workspace_id || "") === prioritySpaceId ? 0 : 1
      return aPriority - bPriority
    })
    for (var paneIndex = 0; paneIndex < orderedPanes.length; paneIndex++) {
      var pane = orderedPanes[paneIndex]
      var paneId = String(pane.pane_id || "")
      var terminalId = String(pane.terminal_id || "")
      if (paneId === "") continue
      var appId = IdCodec.appId(paneId)
      expected[appId] = pane
      if (terminalId === "") {
        unavailable++
        continue
      }
      var matches = topsForAppId(appId)
      if (matches.length > 1) {
        state = "error"
        errorMessage = "duplicate managed windows for " + paneId
        unavailablePaneCount = unavailable
        return
      }
      if (matches.length === 1) {
        if (reattachingTerminalIds[appId]) {
          state = "preparing"
          return
        }
        if (attachedTerminalIds[appId]
            && attachedTerminalIds[appId] !== terminalId) {
          closeTop(matches[0], appId)
          setMapValue("reattachingTerminalIds", appId, terminalId)
          beginSettling("reattach:" + appId + ":" + terminalId)
          state = "preparing"
          return
        }
        attached++
        markManaged(appId, true)
        rememberTerminal(appId, terminalId)
        setMapValue("failedTerminalIds", appId, "")
        if (pendingAppId === appId) {
          pendingPaneId = ""
          pendingAppId = ""
          pendingCommand = ""
          launchTimeout.stop()
        }
        var paneSpaceId = String(pane.workspace_id || "")
        var targetId = targetWorkspaceId(paneSpaceId, homes)
        if (targetId && topWorkspaceId(matches[0]) !== targetId) {
          moveTop(matches[0], targetId, paneSpaceId, appId)
          state = "preparing"
          return
        }
        if (!stableWorkspace(paneSpaceId)) {
          var currentWorkspace = workspaceById(targetId)
          if (currentWorkspace) {
            renameWorkspace(currentWorkspace, paneSpaceId, Number(homes[paneSpaceId]))
            state = "preparing"
            return
          }
        } else if (pendingSpaceId === paneSpaceId) {
          pendingSpaceId = ""
          pendingHomeId = 0
        }
      } else if (reattachingTerminalIds[appId]) {
        rememberTerminal(appId, "")
        setMapValue("reattachingTerminalIds", appId, "")
      }
    }

    var managed = Object.keys(managedAppIds)
    for (var managedIndex = 0; managedIndex < managed.length; managedIndex++) {
      var managedId = managed[managedIndex]
      if (expected[managedId]) continue
      var stale = topsForAppId(managedId)
      if (stale.length === 1) closeTop(stale[0], managedId)
      markManaged(managedId, false)
      rememberTerminal(managedId, "")
      setMapValue("reattachingTerminalIds", managedId, "")
      setMapValue("failedTerminalIds", managedId, "")
      settleTimer.restart()
      state = "preparing"
      return
    }

    if (pendingPaneId !== "") {
      state = "preparing"
      return
    }

    for (var missingIndex = 0; missingIndex < orderedPanes.length; missingIndex++) {
      var missing = orderedPanes[missingIndex]
      var missingPaneId = String(missing.pane_id || "")
      if (missingPaneId === "" || String(missing.terminal_id || "") === "") continue
      var missingAppId = IdCodec.appId(missingPaneId)
      if (topsForAppId(missingAppId).length === 0) {
        if (attachedTerminalIds[missingAppId] === String(missing.terminal_id || "")) {
          unavailable++
          continue
        }
        if (failedTerminalIds[missingAppId] === String(missing.terminal_id || "")) {
          unavailable++
          continue
        }
        var missingSpaceId = String(missing.workspace_id || "")
        var missingTarget = targetWorkspaceId(missingSpaceId, homes)
        if (!missingTarget) {
          state = "error"
          errorMessage = "no home workspace ID for " + missingSpaceId
          return
        }
        launchPane(missing, missingTarget)
        state = "preparing"
        return
      }
    }

    attachedPaneCount = attached
    unavailablePaneCount = unavailable
    prioritySpaceId = ""
    state = "ready"
    settlingKey = ""
    reconciliationComplete()
  }

  function spaceReady(spaceId) {
    var expectedPanes = panesForSpace(spaceId)
    var target = stableWorkspace(spaceId)
    if (!target || expectedPanes.length === 0) return false
    var targetId = target.parsed.leased ? target.parsed.slotId : target.parsed.homeId
    for (var i = 0; i < expectedPanes.length; i++) {
      var paneId = String(expectedPanes[i].pane_id || "")
      if (String(expectedPanes[i].terminal_id || "") === ""
          || topsForAppId(IdCodec.appId(paneId)).length !== 1
          || attachedTerminalIds[IdCodec.appId(paneId)] !== String(expectedPanes[i].terminal_id || "")
          || topWorkspaceId(topsForAppId(IdCodec.appId(paneId))[0]) !== targetId) return false
    }
    return true
  }

  function prepareSpace(spaceId) {
    prioritySpaceId = String(spaceId || "")
    errorMessage = ""
    var expectedPanes = panesForSpace(prioritySpaceId)
    for (var i = 0; i < expectedPanes.length; i++) {
      var appId = IdCodec.appId(String(expectedPanes[i].pane_id || ""))
      if (topsForAppId(appId).length === 0) {
        rememberTerminal(appId, "")
        setMapValue("failedTerminalIds", appId, "")
      }
    }
    schedule()
    return "preparing"
  }

  function focusPane(paneId) {
    var pane = null
    for (var i = 0; i < panes.length; i++)
      if (String(panes[i].pane_id || "") === String(paneId || "")) pane = panes[i]
    if (!pane) return "unknown pane: " + paneId
    var matches = topsForAppId(IdCodec.appId(paneId))
    if (matches.length === 1) {
      var appId = IdCodec.appId(paneId)
      var address = topAddress(matches[0])
      Hyprland.dispatch("function() local window = hl.get_window(" + luaString("address:" + address) + "); "
        + "if window and window.class == " + luaString(appId) + " then hl.dispatch(hl.dsp.focus({ window = window })) end end")
      return "ok"
    }
    if (matches.length > 1) return "duplicate managed pane windows"
    rememberTerminal(IdCodec.appId(paneId), "")
    setMapValue("failedTerminalIds", IdCodec.appId(paneId), "")
    prioritySpaceId = String(pane.workspace_id || "")
    schedule()
    return String(pane.terminal_id || "") === "" ? "pane has no terminal" : "preparing"
  }

  onSpacesChanged: schedule()
  onPanesChanged: schedule()
  onEnabledChanged: {
    if (!enabled) {
      inventoryReady = false
      state = "disabled"
      return
    }
    inventoryReady = false
    Hyprland.refreshWorkspaces()
    Hyprland.refreshToplevels()
    initialInventoryTimer.restart()
  }
  Component.onCompleted: if (enabled) {
    Hyprland.refreshWorkspaces()
    Hyprland.refreshToplevels()
    initialInventoryTimer.restart()
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      settleTimer.restart()
    }
  }

  Connections {
    target: root.leaseCoordinator
    function onBusyChanged() {
      if (!root.leaseCoordinator.busy) root.schedule()
    }
    function onRecoveryRequiredChanged() {
      if (!root.leaseCoordinator.recoveryRequired) root.schedule()
    }
  }

  Timer {
    id: reconcileTimer
    interval: 0
    repeat: false
    onTriggered: root.reconcile()
  }

  Timer {
    id: initialInventoryTimer
    interval: 200
    repeat: false
    onTriggered: {
      root.inventoryReady = true
      root.schedule()
    }
  }

  Timer {
    id: settleTimer
    interval: 80
    repeat: false
    onTriggered: {
      if (root.state === "preparing" && root.settleAttempts >= 99) {
        root.state = "error"
        root.errorMessage = "workspace preparation did not settle"
        return
      }
      Hyprland.refreshWorkspaces()
      Hyprland.refreshToplevels()
      reconcileTimer.restart()
      if (root.state === "preparing") {
        root.settleAttempts++
        restart()
      }
    }
  }

  Timer {
    id: launchTimeout
    interval: 8000
    repeat: false
    onTriggered: {
      var failedAppId = root.pendingAppId
      var failedPaneId = root.pendingPaneId
      for (var i = 0; i < root.panes.length; i++) {
        if (String(root.panes[i].pane_id || "") === failedPaneId)
          root.setMapValue("failedTerminalIds", failedAppId, String(root.panes[i].terminal_id || ""))
      }
      root.pendingPaneId = ""
      root.pendingAppId = ""
      root.pendingSpaceId = ""
      root.pendingHomeId = 0
      root.markManaged(failedAppId, false)
      root.state = "error"
      root.errorMessage = "terminal did not open"
    }
  }
}
