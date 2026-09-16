import QtQuick
import Quickshell
import "LayoutSync.js" as LayoutSync

ShellRoot {
  id: root

  function run() {
    var layout = {
      area: { x: 18, y: 1, width: 186, height: 53 },
      panes: [
        { pane_id: "w:p1", rect: { x: 18, y: 1, width: 64, height: 53 } },
        { pane_id: "w:p2", rect: { x: 82, y: 1, width: 122, height: 40 } },
        { pane_id: "w:p4", rect: { x: 82, y: 41, width: 122, height: 13 } }
      ],
      splits: [
        { id: "root", direction: "right", ratio: 0.34408602,
          rect: { x: 18, y: 1, width: 186, height: 53 } },
        { id: "right", direction: "down", ratio: 0.75000006,
          rect: { x: 82, y: 1, width: 122, height: 53 } }
      ]
    }
    var current = [
      { paneId: "w:p4", rect: { x: 12, y: 38, width: 749, height: 910 } },
      { paneId: "w:p2", rect: { x: 775, y: 38, width: 749, height: 448 } },
      { paneId: "w:p1", rect: { x: 775, y: 500, width: 749, height: 448 } }
    ]
    var analysis = LayoutSync.analyze(layout, current)
    if (!analysis.compatible
        || analysis.herdrShape !== "r(p,d(p,p))"
        || analysis.swaps.length !== 1
        || analysis.swaps[0].firstPaneId !== "w:p4"
        || analysis.swaps[0].secondPaneId !== "w:p1"
        || analysis.imports.length !== 2) {
      console.error("LAYOUT_SYNC_FAILED", JSON.stringify(analysis))
      Qt.quit()
      return
    }

    var migrated = [
      { paneId: "w:p1", rect: { x: 12, y: 38, width: 506, height: 910 } },
      { paneId: "w:p2", rect: { x: 532, y: 38, width: 992, height: 668 } },
      { paneId: "w:p4", rect: { x: 532, y: 720, width: 992, height: 228 } }
    ]
    var settled = LayoutSync.analyze(layout, migrated)
    if (!settled.compatible || settled.swaps.length !== 0 || settled.imports.length !== 0) {
      console.error("LAYOUT_SYNC_FAILED", JSON.stringify(settled))
      Qt.quit()
      return
    }

    console.log("LAYOUT_SYNC_OK")
    Qt.quit()
  }

  Timer {
    interval: 0
    running: true
    repeat: false
    onTriggered: root.run()
  }
}
