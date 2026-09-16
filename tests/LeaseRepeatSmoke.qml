import QtQuick
import Quickshell
import Quickshell.Hyprland

ShellRoot {
  property int step: 0

  WorkspaceLease {
    id: lease
    minimumSlotId: 193
    maximumSlotId: 194

    onOperationFinished: function(operation, success, message) {
      if (!success) {
        console.error("LEASE_REPEAT_FAILED", operation, message, lease.phase, lease.errorMessage)
        Qt.quit()
        return
      }
      if (operation === "acquire" && step === 1) {
        step = 2
        var released = lease.release()
        if (released !== "requested") {
          console.error("LEASE_REPEAT_FAILED", "release", released)
          Qt.quit()
        }
      } else if (operation === "release" && step === 2) {
        step = 3
        var again = lease.acquire("w1")
        if (again !== "requested") {
          console.error("LEASE_REPEAT_FAILED", "reacquire", again)
          Qt.quit()
        }
      } else if (operation === "acquire" && step === 3) {
        if (!lease.active || lease.slotId !== 193 || lease.ownerSpaceId !== "w1") {
          console.error("LEASE_REPEAT_FAILED", "inactive", lease.active, lease.slotId, lease.ownerSpaceId)
          Qt.quit()
          return
        }
        step = 4
        var finalRelease = lease.release()
        if (finalRelease !== "requested") {
          console.error("LEASE_REPEAT_FAILED", "final release", finalRelease)
          Qt.quit()
        }
      } else if (operation === "release" && step === 4) {
        console.log("LEASE_REPEAT_OK")
        Qt.quit()
      } else {
        console.error("LEASE_REPEAT_FAILED", "unexpected", operation, step)
        Qt.quit()
      }
    }
  }

  Timer {
    interval: 500
    running: true
    onTriggered: {
      Hyprland.dispatch('hl.dsp.focus({ workspace = "193" })')
      startTimer.restart()
    }
  }

  Timer {
    id: startTimer
    interval: 200
    repeat: false
    onTriggered: {
      step = 1
      var result = lease.acquire("w1")
      if (result !== "requested") {
        console.error("LEASE_REPEAT_FAILED", "acquire", result)
        Qt.quit()
      }
    }
  }

  Timer {
    interval: 8000
    running: true
    onTriggered: {
      console.error("LEASE_REPEAT_TIMEOUT", step, lease.phase, lease.errorMessage)
      Qt.quit()
    }
  }
}