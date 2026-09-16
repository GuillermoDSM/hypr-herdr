import QtQuick
import Quickshell
import "IdCodec.js" as IdCodec
import "LeaseCodec.js" as LeaseCodec

ShellRoot {
  HerdrClient {
    id: client

    onSnapshotApplied: {
      var encoded = IdCodec.encode("w1")
      var lease = LeaseCodec.parseHerdr(LeaseCodec.leasedName(1000000001, encoded, 2, IdCodec.encode("2"), 2000000002))
      if (state === "ready" && protocol === 20
          && IdCodec.workspaceName("w1") === "herdr:dzE"
          && IdCodec.decode(encoded) === "w1"
          && layouts.length === tabs.length
          && lease && lease.leased && lease.slotId === 2 && lease.homeId === 1000000001)
        console.log("HERDR_SMOKE_OK", state, protocol, workspaces.length, tabs.length, panes.length, layouts.length)
      else
        console.error("HERDR_SMOKE_FAILED", state, protocol, IdCodec.workspaceName("w1"))
      Qt.quit()
    }
  }

  Timer {
    interval: 5000
    running: true
    onTriggered: {
      console.error("HERDR_SMOKE_TIMEOUT", client.state, client.errorMessage)
      Qt.quit()
    }
  }
}
