import QtQuick
import Quickshell
import "AttachConfig.js" as AttachConfig

ShellRoot {
  property var failures: []

  function check(name, actual, expected) {
    if (actual !== expected) failures = failures.concat([name + " -> " + JSON.stringify(actual)])
  }

  Timer {
    interval: 100
    running: true
    onTriggered: {
      check("empty", AttachConfig.mergeMouseCapture(""),
        "[ui]\nmouse_capture = false\n")

      var withUi = "onboarding = false\n[ui]\nagent_panel_sort = \"priority\"\n\n[ui.toast]\ndelivery = \"off\"\n"
      check("withUi", AttachConfig.mergeMouseCapture(withUi),
        "onboarding = false\n[ui]\nmouse_capture = false\nagent_panel_sort = \"priority\"\n\n[ui.toast]\ndelivery = \"off\"\n")

      check("noUi", AttachConfig.mergeMouseCapture("onboarding = false\n"),
        "onboarding = false\n\n[ui]\nmouse_capture = false\n")

      var explicit = "[ui]\nmouse_capture = true\n"
      check("explicit", AttachConfig.mergeMouseCapture(explicit), explicit)

      check("inlineComment", AttachConfig.mergeMouseCapture("onboarding = false\n[ui] # ui section\nhost_cursor = \"auto\"\n"),
        "onboarding = false\n[ui] # ui section\nmouse_capture = false\nhost_cursor = \"auto\"\n")

      if (failures.length === 0)
        console.log("ATTACH_CONFIG_OK")
      else
        console.error("ATTACH_CONFIG_FAILED", failures.join(" | "))
      Qt.quit()
    }
  }
}