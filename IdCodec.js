.pragma library

function utf8Bytes(value) {
  var text = String(value)
  var bytes = []
  for (var i = 0; i < text.length; i++) {
    var code = text.charCodeAt(i)
    if (code >= 0xd800 && code <= 0xdbff && i + 1 < text.length) {
      var low = text.charCodeAt(i + 1)
      if (low >= 0xdc00 && low <= 0xdfff) {
        code = 0x10000 + ((code - 0xd800) << 10) + low - 0xdc00
        i++
      }
    }

    if (code < 0x80) {
      bytes.push(code)
    } else if (code < 0x800) {
      bytes.push(0xc0 | (code >> 6), 0x80 | (code & 0x3f))
    } else if (code < 0x10000) {
      bytes.push(0xe0 | (code >> 12), 0x80 | ((code >> 6) & 0x3f), 0x80 | (code & 0x3f))
    } else {
      bytes.push(0xf0 | (code >> 18), 0x80 | ((code >> 12) & 0x3f),
                 0x80 | ((code >> 6) & 0x3f), 0x80 | (code & 0x3f))
    }
  }
  return bytes
}

function encode(value) {
  var bytes = utf8Bytes(value)
  return String(Qt.btoa(bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "")
}

function workspaceName(id) {
  return "herdr:" + encode(id)
}

function appId(id) {
  return "herdr-pane-" + encode(id)
}
