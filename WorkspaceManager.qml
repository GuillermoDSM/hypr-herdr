import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "IdCodec.js" as IdCodec
import "LayoutSync.js" as LayoutSync
import "LeaseCodec.js" as LeaseCodec

Item {
  id: root
  visible: false

  property var spaces: []
  property var panes: []
  property var layouts: []
  property var leaseCoordinator: null
  property bool enabled: false
  property bool layoutSyncEnabled: false
  property bool layoutWriteBusy: false
  property string persistenceKey: "default"
  property string testLauncher: ""
  property int testHomeBase: 0
  property string prioritySpaceId: ""
  property string pendingPaneId: ""
  property string pendingAppId: ""
  property string pendingCommand: ""
  property string pendingSpaceId: ""
  property int pendingHomeId: 0
  property alias managedAppIds: persisted.managedAppIds
  property alias attachedTerminalIds: persisted.attachedTerminalIds
  property alias reattachingTerminalIds: persisted.reattachingTerminalIds
  property alias failedTerminalIds: persisted.failedTerminalIds
  property string state: enabled ? "preparing" : "disabled"
  property string errorMessage: ""
  property int attachedPaneCount: 0
  property int unavailablePaneCount: 0
  property int settleAttempts: 0
  property string settlingKey: ""
  property bool inventoryReady: false
  property string layoutState: layoutSyncEnabled ? "waiting" : "disabled"
  property string layoutErrorMessage: ""
  property bool layoutSettingsLoaded: false
  property var initializedLayouts: ({})
  property var failedLayoutMigrations: ({})
  property string pendingLayoutSpaceId: ""
  property string pendingLayoutSignature: ""
  property int layoutSettleAttempts: 0
  property string lastRatioUpdateKey: ""

  readonly property string layoutSettingsPath: Quickshell.statePath("hypr-herdr-layouts.json")

  readonly property bool preparing: enabled && state === "preparing"
  readonly property bool ready: enabled && state === "ready"

  signal reconciliationComplete()
  signal layoutRatioUpdates(var updates)

  PersistentProperties {
    id: persisted
    reloadableId: "hypr-herdr-workspace-manager:" + root.persistenceKey
    property var managedAppIds: ({})
    property var attachedTerminalIds: ({})
    property var reattachingTerminalIds: ({})
    property var failedTerminalIds: ({})
  }

  FileView {
    id: layoutSettingsFile
    path: root.layoutSettingsPath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadLayoutSettings(text())
    onLoadFailed: root.loadLayoutSettings("")
  }

  function loadLayoutSettings(raw) {
    if (layoutSettingsLoaded) return
    try {
      var parsed = JSON.parse(String(raw || "{}"))
      initializedLayouts = parsed && parsed.initializedLayouts
        && typeof parsed.initializedLayouts === "object" ? parsed.initializedLayouts : ({})
    } catch (error) {
      console.warn("hypr-herdr: could not parse layout settings:", error)
      initializedLayouts = ({})
    }
    layoutSettingsLoaded = true
    scheduleLayoutSync()
  }

  function saveLayoutSettings() {
    if (!layoutSettingsLoaded) return
    layoutSettingsFile.setText(JSON.stringify({ version: 1, initializedLayouts: initializedLayouts }, null, 2) + "\n")
  }

  function layoutPaneSignature(layout) {
    var ids = []
    var values = layout && Array.isArray(layout.panes) ? layout.panes : []
    for (var i = 0; i < values.length; i++) ids.push(String(values[i].pane_id || ""))
    ids.sort()
    return ids.join("\n")
  }

  function markLayoutInitialized(spaceId, signature) {
    var next = Object.assign({}, initializedLayouts)
    next[String(spaceId)] = String(signature)
    initializedLayouts = next
    saveLayoutSettings()
  }

  function invalidateLayout(spaceId) {
    var key = String(spaceId || "")
    if (key === "" || initializedLayouts[key] === undefined) return
    var next = Object.assign({}, initializedLayouts)
    delete next[key]
    initializedLayouts = next
    saveLayoutSettings()
  }

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

  function topRect(top) {
    var ipc = top ? (top.lastIpcObject || {}) : {}
    var at = ipc.at || []
    var size = ipc.size || []
    return {
      x: Number(at[0] || 0),
      y: Number(at[1] || 0),
      width: Number(size[0] || 0),
      height: Number(size[1] || 0)
    }
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

  function activeHerdrSpaceId() {
    var focused = Hyprland.focusedWorkspace
    var focusedId = workspaceId(focused)
    for (var i = 0; i < spaces.length; i++) {
      var spaceId = String(spaces[i].workspace_id || "")
      var stable = stableWorkspace(spaceId)
      if (stable && workspaceId(stable.workspace) === focusedId) return spaceId
    }
    return ""
  }

  function layoutForSpace(spaceId) {
    var space = spaceForId(spaceId)
    var activeTabId = String((space && space.active_tab_id) || "")
    var fallback = null
    for (var i = 0; i < layouts.length; i++) {
      if (String(layouts[i].workspace_id || "") !== String(spaceId)) continue
      if (String(layouts[i].tab_id || "") === activeTabId) return layouts[i]
      if (!fallback) fallback = layouts[i]
    }
    return fallback
  }

  function windowsForLayout(layout) {
    var result = []
    var values = layout && Array.isArray(layout.panes) ? layout.panes : []
    for (var i = 0; i < values.length; i++) {
      var paneId = String(values[i].pane_id || "")
      var matches = topsForAppId(IdCodec.appId(paneId))
      if (matches.length !== 1) return null
      result.push({ paneId: paneId, rect: topRect(matches[0]) })
    }
    return result
  }

  function scheduleLayoutSync() {
    if (layoutSyncEnabled && enabled && ready && layoutSettingsLoaded) layoutSyncTimer.restart()
  }

  function dispatchLayoutMigration(spaceId, signature, analysis) {
    var code = "function() local original = hl.get_active_window(); "
    for (var swapIndex = 0; swapIndex < analysis.swaps.length; swapIndex++) {
      var swap = analysis.swaps[swapIndex]
      var firstId = IdCodec.appId(String(swap.firstPaneId || ""))
      var secondId = IdCodec.appId(String(swap.secondPaneId || ""))
      code += "local a = hl.get_window(" + luaString("class:" + firstId) + "); "
        + "local b = hl.get_window(" + luaString("class:" + secondId) + "); "
        + "if a and b then hl.dispatch(hl.dsp.focus({ window = a })); "
        + "hl.dispatch(hl.dsp.window.swap({ target = b })); end; "
    }
    for (var ratioIndex = 0; ratioIndex < analysis.imports.length; ratioIndex++) {
      var operation = analysis.imports[ratioIndex]
      var appId = IdCodec.appId(String(operation.paneId || ""))
      var ratio = Math.max(0.1, Math.min(1.9, Number(operation.ratio || 0.5) * 2))
      code += "local w = hl.get_window(" + luaString("class:" + appId) + "); "
        + "if w then hl.dispatch(hl.dsp.focus({ window = w })); "
        + "hl.dispatch(hl.dsp.layout(" + luaString("splitratio " + ratio.toFixed(8) + " exact") + ")); end; "
    }
    code += "if original then hl.dispatch(hl.dsp.focus({ window = original })); end; end"

    pendingLayoutSpaceId = String(spaceId)
    pendingLayoutSignature = String(signature)
    layoutSettleAttempts = 0
    layoutState = "migrating"
    layoutErrorMessage = ""
    Hyprland.dispatch(code)
    layoutSettleTimer.restart()
  }

  function finishLayoutMigration(success, message) {
    var spaceId = pendingLayoutSpaceId
    var signature = pendingLayoutSignature
    pendingLayoutSpaceId = ""
    pendingLayoutSignature = ""
    layoutSettleAttempts = 0
    if (success) {
      markLayoutInitialized(spaceId, signature)
      layoutState = "ready"
      layoutErrorMessage = ""
      scheduleLayoutSync()
      return
    }
    var failures = Object.assign({}, failedLayoutMigrations)
    failures[spaceId] = signature
    failedLayoutMigrations = failures
    layoutState = "error"
    layoutErrorMessage = String(message || "Wayland layout migration did not settle")
  }

  function syncActiveLayout(verifying) {
    if (!layoutSyncEnabled || !enabled || !ready || !layoutSettingsLoaded) return
    var spaceId = activeHerdrSpaceId()
    if (spaceId === "") {
      if (pendingLayoutSpaceId === "") layoutState = "waiting"
      return
    }
    if (pendingLayoutSpaceId !== "" && pendingLayoutSpaceId !== spaceId) return

    var layout = layoutForSpace(spaceId)
    if (!layout) {
      layoutState = "waiting"
      return
    }
    var windows = windowsForLayout(layout)
    var stable = stableWorkspace(spaceId)
    if (!windows || !stable || workspaceWindowCount(stable.workspace) !== windows.length) {
      layoutState = "blocked"
      layoutErrorMessage = "layout sync requires one managed window per pane and no extra tiled windows"
      return
    }

    var analysis = LayoutSync.analyze(layout, windows)
    if (!analysis.compatible) {
      layoutState = "blocked"
      layoutErrorMessage = String(analysis.error || "Herdr and Wayland layouts are incompatible")
      return
    }
    var signature = layoutPaneSignature(layout)

    if (pendingLayoutSpaceId !== "") {
      if (analysis.swaps.length === 0 && analysis.imports.length === 0) {
        finishLayoutMigration(true, "")
      } else if (verifying && ++layoutSettleAttempts >= 20) {
        finishLayoutMigration(false, "Wayland did not confirm the requested layout")
      } else {
        layoutSettleTimer.restart()
      }
      return
    }

    if (initializedLayouts[spaceId] !== signature) {
      if (failedLayoutMigrations[spaceId] === signature) {
        layoutState = "error"
        layoutErrorMessage = "layout migration is blocked until the pane set changes"
        return
      }
      if (analysis.swaps.length > 0 || analysis.imports.length > 0) {
        dispatchLayoutMigration(spaceId, signature, analysis)
      } else {
        markLayoutInitialized(spaceId, signature)
        layoutState = "ready"
        layoutErrorMessage = ""
      }
      return
    }

    if (analysis.swaps.length > 0) {
      layoutState = "blocked"
      layoutErrorMessage = "Herdr pane order differs from the authoritative Wayland layout"
      return
    }

    if (layoutWriteBusy) {
      layoutState = "syncing"
      return
    }

    var updates = []
    for (var updateIndex = 0; updateIndex < analysis.updates.length; updateIndex++) {
      updates.push({
        tabId: String(layout.tab_id || ""),
        path: analysis.updates[updateIndex].path,
        ratio: analysis.updates[updateIndex].ratio
      })
    }
    var updateKey = JSON.stringify(updates)
    if (updates.length > 0 && updateKey !== lastRatioUpdateKey) {
      lastRatioUpdateKey = updateKey
      layoutRatioUpdates(updates)
      layoutState = "syncing"
      layoutErrorMessage = ""
    } else if (updates.length === 0) {
      lastRatioUpdateKey = ""
      layoutState = "ready"
      layoutErrorMessage = ""
    }
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

  function stopTransientWork() {
    reconcileTimer.stop()
    initialInventoryTimer.stop()
    settleTimer.stop()
    launchTimeout.stop()
    layoutSyncTimer.stop()
    layoutSettleTimer.stop()
    inventoryReady = false
    pendingPaneId = ""
    pendingAppId = ""
    pendingCommand = ""
    pendingSpaceId = ""
    pendingHomeId = 0
    settlingKey = ""
    settleAttempts = 0
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
    invalidateLayout(String(pane.workspace_id || ""))
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
    scheduleLayoutSync()
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
  onPanesChanged: { schedule(); scheduleLayoutSync() }
  onLayoutsChanged: scheduleLayoutSync()
  onLayoutSyncEnabledChanged: scheduleLayoutSync()
  onLayoutWriteBusyChanged: if (!layoutWriteBusy) scheduleLayoutSync()
  onEnabledChanged: {
    if (!enabled) {
      stopTransientWork()
      state = "disabled"
      return
    }
    inventoryReady = false
    Hyprland.refreshWorkspaces()
    Hyprland.refreshToplevels()
    initialInventoryTimer.restart()
  }
  Component.onCompleted: {
    layoutSettingsFile.reload()
    if (enabled) {
      Hyprland.refreshWorkspaces()
      Hyprland.refreshToplevels()
      initialInventoryTimer.restart()
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      settleTimer.restart()
      root.scheduleLayoutSync()
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
    id: layoutSyncTimer
    interval: 100
    repeat: false
    onTriggered: root.syncActiveLayout(false)
  }

  Timer {
    id: layoutSettleTimer
    interval: 100
    repeat: false
    onTriggered: {
      Hyprland.refreshToplevels()
      root.syncActiveLayout(true)
    }
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
