import QtQuick
import Quickshell
import Quickshell.Hyprland

ShellRoot {
  property int attempts: 0

  Timer {
    interval: 100
    running: true
    repeat: true
    onTriggered: {
      attempts++
      var owner = Quickshell.env("SPIKE_OWNER_NAME")
      var parked = Quickshell.env("SPIKE_PARKED_NAME")
      var ownerFound = false
      var parkedFound = false
      var values = Hyprland.workspaces.values
      for (var i = 0; i < values.length; i++) {
        ownerFound = ownerFound || String(values[i].name || "") === owner
        parkedFound = parkedFound || String(values[i].name || "") === parked
      }

      if (ownerFound && parkedFound) {
        console.log("LEASE_PROBE_OK", owner, parked)
        Qt.quit()
      } else if (attempts >= 20) {
        console.error("LEASE_PROBE_FAILED", ownerFound, parkedFound)
        Qt.quit()
      }
    }
  }
}
