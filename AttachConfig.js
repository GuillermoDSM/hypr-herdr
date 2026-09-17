.pragma library

// The attach clients read `ui.mouse_capture` from the user's Herdr config.
// Managed terminal windows must behave like plain terminals, so we hand them a
// copy of the user's config with mouse capture disabled. An explicit
// `mouse_capture` in the user's file is respected.
function mergeMouseCapture(source) {
  var text = String(source || "")
  var lines = text.length > 0 ? text.split("\n") : []
  var uiHeader = -1
  var hasMouseCapture = false
  var inUi = false
  for (var i = 0; i < lines.length; i++) {
    var trimmed = lines[i].replace(/^\s+|\s+$/g, "")
    var header = trimmed.match(/^\[([^\]]+)\]/)
    if (header) {
      inUi = header[1] === "ui"
      if (inUi && uiHeader === -1) uiHeader = i
      continue
    }
    if (inUi && /^mouse_capture\s*=/.test(trimmed)) hasMouseCapture = true
  }
  if (hasMouseCapture) return text
  if (uiHeader >= 0) {
    lines.splice(uiHeader + 1, 0, "mouse_capture = false")
    return lines.join("\n")
  }
  var base = lines.join("\n").replace(/\s+$/, "")
  return base + (base.length > 0 ? "\n\n" : "") + "[ui]\nmouse_capture = false\n"
}
