import QtQuick
import Quickshell
import qs.Commons

ShellRoot {
  Panel {
    id: panel
    manifest: ({ id: "guillermodsm.hypr-herdr" })
    preparationEnabled: false
  }

  function linear(channel) {
    return channel <= 0.04045 ? channel / 12.92 : Math.pow((channel + 0.055) / 1.055, 2.4)
  }

  function luminance(color) {
    return 0.2126 * linear(color.r) + 0.7152 * linear(color.g) + 0.0722 * linear(color.b)
  }

  function composite(foreground, background) {
    return Qt.rgba(
      foreground.r * foreground.a + background.r * (1 - foreground.a),
      foreground.g * foreground.a + background.g * (1 - foreground.a),
      foreground.b * foreground.a + background.b * (1 - foreground.a),
      1)
  }

  function contrastRatio(first, second) {
    var a = luminance(first)
    var b = luminance(second)
    var high = Math.max(a, b)
    var low = Math.min(a, b)
    return (high + 0.05) / (low + 0.05)
  }

  Timer {
    interval: 3000
    running: true
    onTriggered: {
      var status = JSON.parse(panel.statusJson())
      var background = Color.popups.background
      var primaryRatio = contrastRatio(panel.foreground, background)
      var secondaryRatio = contrastRatio(composite(panel.dim, background), background)
      var statuses = ["working", "blocked", "done", "idle", "unknown"]
      var statusOk = true
      for (var i = 0; i < statuses.length; i++) {
        var ratio = contrastRatio(composite(panel.statusColor(statuses[i]), background), background)
        if (ratio < 3) statusOk = false
      }
      if (status.state === "ready" && status.protocol === 20
          && status.agents >= 0
          && status.layouts >= 0
          && status.panel.width > 0
          && status.panel.widthRatio >= 0.12
          && status.panel.widthRatio <= 0.45
          && primaryRatio >= 4.5 && secondaryRatio >= 4.5 && statusOk)
        console.log("PANEL_SMOKE_OK", status.workspaces, status.tabs, status.panes, status.agents,
                    status.panel.width, status.panel.widthRatio,
                    "contrast=" + primaryRatio.toFixed(2) + "/" + secondaryRatio.toFixed(2))
      else
        console.error("PANEL_SMOKE_FAILED", panel.statusJson(),
                      "contrast=" + primaryRatio.toFixed(2) + "/" + secondaryRatio.toFixed(2),
                      "statusOk=" + statusOk)
      Qt.quit()
    }
  }
}