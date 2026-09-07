import QtQuick
import Quickshell
import Quickshell.Hyprland

ShellRoot {
  property int step: 0

  WorkspaceLease {
    id: lease
    minimumSlotId: 191
    maximumSlotId: 192

    onOperationFinished: function(operation, success, message) {
      if (!success) {
        var names = []
        var values = Hyprland.workspaces.values
        for (var i = 0; i < values.length; i++) {
          var ipc = values[i].lastIpcObject || {}
          names.push(String(values[i].id) + "=" + String(values[i].name || "")
                     + "[ipc:" + String(ipc.id) + "=" + String(ipc.name) + "]")
        }
        console.error("LEASE_COORDINATOR_FAILED", operation, message,
                      "owner=" + lease.ownerSpaceId, "slot=" + lease.slotId, names.join(","))
        Qt.quit()
        return
      }
      if (operation === "acquire") {
        if (step === 5) {
          step = 6
          var emptyReleaseResult = lease.release()
          if (emptyReleaseResult !== "requested") {
            console.error("LEASE_COORDINATOR_FAILED", "empty release", emptyReleaseResult)
            Qt.quit()
          }
          return
        }
        step = 2
        var switchResult = lease.switchSpace("w2")
        if (switchResult !== "requested") {
          console.error("LEASE_COORDINATOR_FAILED", "switch", switchResult)
          Qt.quit()
        }
      } else if (operation === "switch") {
        step = 3
        Hyprland.dispatch('hl.dsp.focus({ workspace = "192" })')
        migrateTimer.restart()
      } else if (operation === "migrate") {
        step = 4
        var releaseResult = lease.release()
        if (releaseResult !== "requested") {
          console.error("LEASE_COORDINATOR_FAILED", "release", releaseResult)
          Qt.quit()
        }
      } else if (operation === "release") {
        if (step === 4) {
          step = 5
          Hyprland.dispatch('hl.dsp.window.close({ window = "class:hypr-herdr-coordinator-smoke-second-slot" })')
          emptyAcquireTimer.restart()
          return
        }
        lease.recoveryRequired = true
        if (lease.acquire("w1") !== "workspace recovery required") {
          console.error("LEASE_COORDINATOR_FAILED", "recovery guard")
          Qt.quit()
          return
        }
        console.log("LEASE_COORDINATOR_OK")
        Qt.quit()
      }
    }
  }

  Timer {
    id: migrateTimer
    interval: 150
    repeat: false
    onTriggered: {
      var result = lease.migrate("w2")
      if (result !== "requested") {
        console.error("LEASE_COORDINATOR_FAILED", "migrate", result)
        Qt.quit()
      }
    }
  }

  Timer {
    id: emptyAcquireTimer
    interval: 300
    repeat: false
    onTriggered: {
      Hyprland.dispatch('hl.dsp.focus({ workspace = "192" })')
      var result = lease.acquire("w1")
      if (result !== "requested") {
        console.error("LEASE_COORDINATOR_FAILED", "empty acquire", result)
        Qt.quit()
      }
    }
  }

  Timer {
    interval: 500
    running: true
    onTriggered: {
      Hyprland.dispatch('hl.dsp.focus({ workspace = "191" })')
      initialAcquireTimer.restart()
    }
  }

  Timer {
    id: initialAcquireTimer
    interval: 150
    repeat: false
    onTriggered: {
      step = 1
      var result = lease.acquire("w1")
      if (result !== "requested") {
        console.error("LEASE_COORDINATOR_FAILED", "acquire", result)
        Qt.quit()
        return
      }
      if (lease.switchSpace("w2") !== "workspace transaction already in progress") {
        console.error("LEASE_COORDINATOR_FAILED", "concurrency guard")
        Qt.quit()
      }
    }
  }

  Timer {
    interval: 5000
    running: true
    onTriggered: {
      console.error("LEASE_COORDINATOR_TIMEOUT", step, lease.phase, lease.errorMessage)
      Qt.quit()
    }
  }
}
