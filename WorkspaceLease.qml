import QtQuick
import Quickshell.Hyprland
import Quickshell.Io
import "IdCodec.js" as IdCodec
import "LeaseCodec.js" as LeaseCodec

Item {
  id: root
  visible: false

  property bool busy: false
  property bool recoveryRequired: false
  property int minimumSlotId: 1
  property int maximumSlotId: 10
  property string phase: "idle"
  property string errorMessage: ""
  property int slotId: 0
  property int homeId: 0
  property int parkingId: 0
  property string ownerSpaceId: ""
  property string originalName: ""
  property string leasedWorkspaceName: ""
  property string parkedWorkspaceName: ""
  property string pendingOperation: ""
  property string pendingSpaceId: ""
  property int pendingSlotId: 0
  property string pendingPreviousParkedName: ""
  property int verificationAttempts: 0
  property var liveWorkspaces: []
  property int liveFocusedId: 0
  property bool liveRefreshQueued: false

  readonly property bool active: slotId > 0 && ownerSpaceId !== ""

  signal operationFinished(string operation, bool success, string message)

  function workspaceValues() {
    return liveWorkspaces
  }

  function workspaceId(workspace) {
    return workspace ? Number(workspace.id || 0) : 0
  }

  function workspaceName(workspace) {
    return workspace ? String(workspace.name || "") : ""
  }

  function workspaceWindowCount(workspace) {
    return workspace && workspace.windows !== undefined ? Number(workspace.windows) : 0
  }

  function workspaceById(id) {
    var values = workspaceValues()
    for (var i = 0; i < values.length; i++) {
      if (workspaceId(values[i]) === Number(id)) return values[i]
    }
    return null
  }

  function focusedWorkspace() {
    return workspaceById(liveFocusedId)
  }

  function refreshLive() {
    if (liveQuery.running || focusedQuery.running) {
      liveRefreshQueued = true
      return
    }
    liveQuery.running = true
    focusedQuery.running = true
  }

  function workspaceByName(name) {
    var values = workspaceValues()
    for (var i = 0; i < values.length; i++) {
      if (workspaceName(values[i]) === String(name || "")) return values[i]
    }
    return null
  }

  function parsedHerdrWorkspace(spaceId) {
    var values = workspaceValues()
    for (var i = 0; i < values.length; i++) {
      var parsed = LeaseCodec.parseHerdr(workspaceName(values[i]))
      if (parsed && decodeToken(parsed.encodedSpaceId) === String(spaceId || ""))
        return { workspace: values[i], parsed: parsed }
    }
    return null
  }

  function spaceIdForName(name) {
    var parsed = LeaseCodec.parseHerdr(name)
    if (parsed) return decodeToken(parsed.encodedSpaceId)
    var legacy = String(name || "")
    if (legacy.indexOf("herdr:") === 0 && legacy.indexOf("herdr:v1:") !== 0)
      return decodeToken(legacy.slice(6))
    return ""
  }

  function decodeToken(value) {
    try {
      var decoded = IdCodec.decode(value)
      return IdCodec.encode(decoded) === value ? decoded : ""
    } catch (error) {
      return ""
    }
  }

  function luaString(value) {
    return JSON.stringify(String(value))
  }

  function namedWorkspace(name) {
    return "name:" + String(name)
  }

  function workspacePrepared(entry) {
    return entry && entry.workspace && workspaceWindowCount(entry.workspace) > 0
  }

  function freeHomeId(spaceId) {
    for (var attempt = 0; attempt < 10000; attempt++) {
      var candidate = LeaseCodec.homeCandidate(spaceId, attempt)
      var existing = workspaceById(candidate)
      if (!existing) return candidate
      var parsed = LeaseCodec.parseHerdr(workspaceName(existing))
      if (parsed && decodeToken(parsed.encodedSpaceId) === String(spaceId)) return candidate
    }
    return 0
  }

  function freeParkingId(slot) {
    for (var attempt = 0; attempt < 10000; attempt++) {
      var candidate = LeaseCodec.parkingCandidate(slot, attempt)
      if (!workspaceById(candidate)) return candidate
    }
    return 0
  }

  function stableName(spaceId, home) {
    return LeaseCodec.stableName(home, IdCodec.encode(spaceId))
  }

  function begin(operation, spaceId, slot) {
    if (busy) return "workspace transaction already in progress"
    busy = true
    phase = operation
    errorMessage = ""
    pendingOperation = operation
    pendingSpaceId = String(spaceId || "")
    pendingSlotId = Number(slot || 0)
    verificationAttempts = 0
    refreshLive()
    verifyTimer.restart()
    return "requested"
  }

  function fail(message) {
    errorMessage = String(message)
    phase = "error"
    return errorMessage
  }

  function acquire(spaceId) {
    if (busy) return "workspace transaction already in progress"
    if (recoveryRequired) return "workspace recovery required"
    if (!Hyprland.usingLua) return fail("Hyprland Lua dispatchers are required")
    reconcile()
    if (active) return switchSpace(spaceId)

    var source = focusedWorkspace()
    var slot = workspaceId(source)
    if (slot < minimumSlotId || slot > maximumSlotId)
      return fail("open Hypr Herdr from a numeric workspace slot")

    var target = parsedHerdrWorkspace(spaceId)
    if (!workspacePrepared(target)) return fail("Herdr space is not prepared yet")
    if (target.parsed.leased) return fail("Herdr space already owns a slot")

    var home = Number(target.parsed.homeId)
    var parking = freeParkingId(slot)
    if (!parking || workspaceById(home) !== target.workspace) return fail("workspace ID collision")

    var encodedOriginal = IdCodec.encode(workspaceName(source) || String(slot))
    var parkedName = LeaseCodec.parkedName(slot, encodedOriginal, parking)
    var leasedName = LeaseCodec.leasedName(home, target.parsed.encodedSpaceId, slot, encodedOriginal, parking)
    var targetSelector = namedWorkspace(workspaceName(target.workspace))
    pendingPreviousParkedName = ""
    var code = "function() "
      + "local source = hl.get_active_workspace(); "
      + "local target = hl.get_workspace(" + luaString(targetSelector) + "); "
      + "if not source or source.id ~= " + slot + " or not target "
      + "or hl.get_workspace(" + parking + ") then return end; "
      + "hl.dispatch(hl.dsp.workspace.rename({ workspace = source, name = " + luaString(parkedName) + " })); "
      + "hl.dispatch(hl.dsp.workspace.change_id({ workspace = source, id = " + parking + " })); "
      + "hl.dispatch(hl.dsp.workspace.rename({ workspace = target, name = " + luaString(leasedName) + " })); "
      + "hl.dispatch(hl.dsp.workspace.change_id({ workspace = target, id = " + slot + " })); "
      + "hl.dispatch(hl.dsp.focus({ workspace = " + luaString(String(slot)) + " })); end"
    Hyprland.dispatch(code)
    return begin("acquire", spaceId, slot)
  }

  function switchSpace(spaceId) {
    if (busy) return "workspace transaction already in progress"
    if (recoveryRequired) return "workspace recovery required"
    reconcile()
    if (!active) return acquire(spaceId)
    if (String(spaceId) === ownerSpaceId) {
      Hyprland.dispatch("hl.dsp.focus({ workspace = " + luaString(String(slotId)) + " })")
      return "requested"
    }

    var target = parsedHerdrWorkspace(spaceId)
    if (!workspacePrepared(target) || target.parsed.leased)
      return fail("Herdr space is not prepared yet")

    var owner = parsedHerdrWorkspace(ownerSpaceId)
    if (!owner || !owner.parsed.leased) return fail("leased workspace is missing")
    var ownerStable = stableName(ownerSpaceId, owner.parsed.homeId)
    var targetLeased = LeaseCodec.leasedName(
      target.parsed.homeId,
      target.parsed.encodedSpaceId,
      slotId,
      owner.parsed.encodedOriginalName,
      parkingId
    )
    pendingPreviousParkedName = ""
    var code = "function() "
      + "local owner = hl.get_workspace(" + luaString(namedWorkspace(workspaceName(owner.workspace))) + "); "
      + "local target = hl.get_workspace(" + luaString(namedWorkspace(workspaceName(target.workspace))) + "); "
      + "if not owner or not target or hl.get_workspace(" + owner.parsed.homeId + ") then return end; "
      + "hl.dispatch(hl.dsp.workspace.rename({ workspace = owner, name = " + luaString(ownerStable) + " })); "
      + "hl.dispatch(hl.dsp.workspace.change_id({ workspace = owner, id = " + owner.parsed.homeId + " })); "
      + "hl.dispatch(hl.dsp.workspace.rename({ workspace = target, name = " + luaString(targetLeased) + " })); "
      + "hl.dispatch(hl.dsp.workspace.change_id({ workspace = target, id = " + slotId + " })); "
      + "hl.dispatch(hl.dsp.focus({ workspace = " + luaString(String(slotId)) + " })); end"
    Hyprland.dispatch(code)
    return begin("switch", spaceId, slotId)
  }

  function migrate(spaceId) {
    if (busy) return "workspace transaction already in progress"
    if (recoveryRequired) return "workspace recovery required"
    reconcile()
    if (!active) return acquire(spaceId)

    var source = focusedWorkspace()
    var newSlot = workspaceId(source)
    if (newSlot < minimumSlotId || newSlot > maximumSlotId || newSlot === slotId)
      return switchSpace(spaceId)

    var target = parsedHerdrWorkspace(spaceId)
    if (!workspacePrepared(target)) return fail("Herdr space is not prepared yet")
    var owner = parsedHerdrWorkspace(ownerSpaceId)
    if (!owner || !owner.parsed.leased) return fail("leased workspace is missing")

    var newParking = freeParkingId(newSlot)
    if (!newParking) return fail("no parking workspace ID is available")
    var encodedOriginal = IdCodec.encode(workspaceName(source) || String(newSlot))
    var newParkedName = LeaseCodec.parkedName(newSlot, encodedOriginal, newParking)
    var ownerStable = stableName(ownerSpaceId, owner.parsed.homeId)
    var targetStable = stableName(spaceId, target.parsed.homeId)
    var newLeasedName = LeaseCodec.leasedName(
      target.parsed.homeId,
      target.parsed.encodedSpaceId,
      newSlot,
      encodedOriginal,
      newParking
    )
    var restoreOld = "local oldParked = hl.get_workspace(" + luaString(namedWorkspace(parkedWorkspaceName)) + "); "
      + "if oldParked then "
      + "hl.dispatch(hl.dsp.workspace.change_id({ workspace = oldParked, id = " + slotId + " })); "
      + "hl.dispatch(hl.dsp.workspace.rename({ workspace = oldParked, name = " + luaString(originalName) + " })); end; "
    var targetLookup = String(spaceId) === ownerSpaceId
      ? namedWorkspace(workspaceName(owner.workspace)) : namedWorkspace(targetStable)
    pendingPreviousParkedName = parkedWorkspaceName
    var code = "function() local source = hl.get_active_workspace(); "
      + "local owner = hl.get_workspace(" + luaString(namedWorkspace(workspaceName(owner.workspace))) + "); "
      + "local target = hl.get_workspace(" + luaString(targetLookup) + "); "
      + "if not source or source.id ~= " + newSlot + " or not owner or not target "
      + "or hl.get_workspace(" + owner.parsed.homeId + ") "
      + "or hl.get_workspace(" + newParking + ") then return end; "
      + "hl.dispatch(hl.dsp.workspace.rename({ workspace = owner, name = " + luaString(ownerStable) + " })); "
      + "hl.dispatch(hl.dsp.workspace.change_id({ workspace = owner, id = " + owner.parsed.homeId + " })); "
      + restoreOld
      + "hl.dispatch(hl.dsp.workspace.rename({ workspace = source, name = " + luaString(newParkedName) + " })); "
      + "hl.dispatch(hl.dsp.workspace.change_id({ workspace = source, id = " + newParking + " })); "
      + (String(spaceId) === ownerSpaceId ? "" : "hl.dispatch(hl.dsp.workspace.rename({ workspace = target, name = " + luaString(targetStable) + " })); ")
      + "hl.dispatch(hl.dsp.workspace.rename({ workspace = target, name = " + luaString(newLeasedName) + " })); "
      + "hl.dispatch(hl.dsp.workspace.change_id({ workspace = target, id = " + newSlot + " })); "
      + "hl.dispatch(hl.dsp.focus({ workspace = " + luaString(String(newSlot)) + " })); end"
    Hyprland.dispatch(code)
    return begin("migrate", spaceId, newSlot)
  }

  function release() {
    if (busy) return "workspace transaction already in progress"
    reconcile()
    if (!active) return recoveryRequired ? "workspace recovery required" : "no active workspace lease"

    var owner = parsedHerdrWorkspace(ownerSpaceId)
    if (!owner || !owner.parsed.leased) return fail("leased workspace is missing")
    var stable = stableName(ownerSpaceId, homeId)
    pendingPreviousParkedName = parkedWorkspaceName

    var restore = "local parked = hl.get_workspace(" + luaString(namedWorkspace(parkedWorkspaceName)) + "); "
      + "if parked then "
      + "hl.dispatch(hl.dsp.workspace.change_id({ workspace = parked, id = " + slotId + " })); "
      + "hl.dispatch(hl.dsp.workspace.rename({ workspace = parked, name = " + luaString(originalName) + " })); "
      + "hl.dispatch(hl.dsp.focus({ workspace = " + luaString(String(slotId)) + " })); "
      + "else hl.dispatch(hl.dsp.focus({ workspace = " + luaString(String(slotId)) + " })); "
      + "local restored = hl.get_active_workspace(); "
      + "hl.dispatch(hl.dsp.workspace.rename({ workspace = restored, name = " + luaString(originalName) + " })); end; "
    var code = "function() "
      + "local owner = hl.get_workspace(" + luaString(namedWorkspace(workspaceName(owner.workspace))) + "); "
      + "if not owner or hl.get_workspace(" + homeId + ") then return end; "
      + "hl.dispatch(hl.dsp.workspace.rename({ workspace = owner, name = " + luaString(stable) + " })); "
      + "hl.dispatch(hl.dsp.workspace.change_id({ workspace = owner, id = " + homeId + " })); "
      + restore + "end"
    var releasedSpace = ownerSpaceId
    var releasedSlot = slotId
    Hyprland.dispatch(code)
    return begin("release", releasedSpace, releasedSlot)
  }

  function toggle(spaceId) {
    reconcile()
    var current = focusedWorkspace()
    if (active && current && workspaceId(current) === slotId
        && spaceIdForName(workspaceName(current)) === ownerSpaceId)
      return release()
    if (active && current && workspaceId(current) >= minimumSlotId && workspaceId(current) <= maximumSlotId)
      return migrate(spaceId)
    if (active) return switchSpace(spaceId)
    return acquire(spaceId)
  }

  function openSpace(spaceId) {
    reconcile()
    if (!active) return acquire(spaceId)
    var current = focusedWorkspace()
    var currentId = workspaceId(current)
    if (currentId >= minimumSlotId && currentId <= maximumSlotId && currentId !== slotId)
      return migrate(spaceId)
    return switchSpace(spaceId)
  }

  function reconcile() {
    var found = []
    var parked = []
    var values = workspaceValues()
    for (var i = 0; i < values.length; i++) {
      var parsed = LeaseCodec.parseHerdr(workspaceName(values[i]))
      if (parsed && parsed.leased) found.push({ workspace: values[i], parsed: parsed })
      var parkedState = LeaseCodec.parseParked(workspaceName(values[i]))
      var parkedName = workspaceName(values[i])
      if (parkedState && !(busy && parkedName === pendingPreviousParkedName))
        parked.push({ workspace: values[i], parsed: parkedState })
    }

    if (found.length > 1) {
      if (!busy) {
        slotId = 0
        ownerSpaceId = ""
        phase = "error"
        errorMessage = "multiple workspace leases require recovery"
        recoveryRequired = true
      }
      return false
    }
    if (found.length === 0) {
      slotId = 0
      homeId = 0
      parkingId = 0
      ownerSpaceId = ""
      originalName = ""
      leasedWorkspaceName = ""
      parkedWorkspaceName = ""
      if (parked.length > 0) {
        if (!busy) {
          phase = "error"
          errorMessage = "orphaned parked workspace requires recovery"
          recoveryRequired = true
        }
        return false
      }
      if (!busy) {
        phase = "idle"
        errorMessage = ""
        recoveryRequired = false
      }
      return true
    }

    var item = found[0]
    var matchingParked = null
    for (var parkedIndex = 0; parkedIndex < parked.length; parkedIndex++) {
      var candidate = parked[parkedIndex]
      if (candidate.parsed.slotId === item.parsed.slotId
          && candidate.parsed.encodedOriginalName === item.parsed.encodedOriginalName
          && candidate.parsed.parkingId === item.parsed.parkingId)
        matchingParked = candidate
    }
    var parkingCollision = workspaceById(item.parsed.parkingId)
    var coherentParked = parked.length === 0
      ? !parkingCollision
      : parked.length === 1 && matchingParked
        && workspaceId(matchingParked.workspace) === item.parsed.parkingId
    if (workspaceId(item.workspace) !== item.parsed.slotId
        || item.parsed.slotId < minimumSlotId || item.parsed.slotId > maximumSlotId
        || !coherentParked) {
      if (!busy) {
        slotId = 0
        ownerSpaceId = ""
        phase = "error"
        errorMessage = "incoherent workspace lease requires recovery"
        recoveryRequired = true
      }
      return false
    }
    slotId = item.parsed.slotId
    homeId = item.parsed.homeId
    parkingId = item.parsed.parkingId
    ownerSpaceId = decodeToken(item.parsed.encodedSpaceId)
    originalName = decodeToken(item.parsed.encodedOriginalName)
    if (ownerSpaceId === "" || originalName === "") {
      slotId = 0
      ownerSpaceId = ""
      phase = "error"
      errorMessage = "invalid workspace lease metadata"
      recoveryRequired = true
      return false
    }
    leasedWorkspaceName = workspaceName(item.workspace)
    parkedWorkspaceName = LeaseCodec.parkedName(slotId, item.parsed.encodedOriginalName, parkingId)
    if (!busy) {
      phase = "active"
      errorMessage = ""
      recoveryRequired = false
    }
    return true
  }

  function liveEventRelevant(name) {
    return name.indexOf("workspace") !== -1 || name === "focusedmon"
      || name === "openwindow" || name === "closewindow" || name === "movewindowv2"
      || name === "activewindowv2"
  }

  Component.onCompleted: {
    refreshLive()
    reconcile()
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = String((event && (event.name || event.event)) || "")
      if (!liveEventRelevant(name)) return
      liveRefreshTimer.restart()
      if (!root.busy) reconcileTimer.restart()
    }
  }

  Timer {
    id: liveRefreshTimer
    interval: 60
    repeat: false
    onTriggered: root.refreshLive()
  }

  Timer {
    id: reconcileTimer
    interval: 80
    repeat: false
    onTriggered: root.reconcile()
  }

  Process {
    id: liveQuery
    command: ["hyprctl", "-j", "workspaces"]
    stdout: StdioCollector { id: liveStdout; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) return
      try {
        var parsed = JSON.parse(String(liveStdout.text || "[]"))
        var next = []
        for (var i = 0; i < parsed.length; i++) {
          next.push({
            id: Number(parsed[i].id),
            name: String(parsed[i].name || ""),
            windows: Number(parsed[i].windows || 0)
          })
        }
        root.liveWorkspaces = next
        if (root.liveRefreshQueued) {
          root.liveRefreshQueued = false
          root.refreshLive()
        }
        if (!root.busy) reconcileTimer.restart()
      } catch (error) {
        console.warn("hypr-herdr: could not parse workspace list:", error)
      }
    }
  }

  Process {
    id: focusedQuery
    command: ["hyprctl", "-j", "activeworkspace"]
    stdout: StdioCollector { id: focusedStdout; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) return
      try {
        var parsed = JSON.parse(String(focusedStdout.text || "{}"))
        root.liveFocusedId = Number(parsed.id || 0)
        if (root.liveRefreshQueued) {
          root.liveRefreshQueued = false
          root.refreshLive()
        }
      } catch (error) {
        console.warn("hypr-herdr: could not parse active workspace:", error)
      }
    }
  }

  Timer {
    id: verifyTimer
    interval: 50
    repeat: false
    onTriggered: {
      if (liveQuery.running || focusedQuery.running || root.liveRefreshQueued) {
        restart()
        return
      }
      var operation = root.pendingOperation
      var expectedSpace = root.pendingSpaceId
      var expectedSlot = root.pendingSlotId
      var coherent = root.reconcile()
      var success = coherent && (operation === "release"
        ? !root.active
        : root.active && root.ownerSpaceId === expectedSpace && root.slotId === expectedSlot)
      if (!success && ++root.verificationAttempts < 20) {
        root.refreshLive()
        restart()
        return
      }
      root.busy = false
      if (!success) {
        root.phase = "error"
        root.errorMessage = operation + " did not reach the expected workspace state"
        root.recoveryRequired = true
      } else if (operation === "release") {
        root.recoveryRequired = false
      }
      root.pendingOperation = ""
      root.pendingSpaceId = ""
      root.pendingSlotId = 0
      root.pendingPreviousParkedName = ""
      root.verificationAttempts = 0
      root.operationFinished(operation, success, success ? "ok" : root.errorMessage)
    }
  }
}
