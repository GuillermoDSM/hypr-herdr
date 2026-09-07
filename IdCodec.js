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

function decode(value) {
  var encoded = String(value || "").replace(/-/g, "+").replace(/_/g, "/")
  while (encoded.length % 4 !== 0) encoded += "="
  var binary = String(Qt.atob(utf8Bytes(encoded)))
  var bytes = []
  for (var i = 0; i < binary.length; i++) bytes.push(binary.charCodeAt(i) & 0xff)

  var result = ""
  for (var offset = 0; offset < bytes.length;) {
    var first = bytes[offset++]
    var code
    if (first < 0x80) {
      code = first
    } else if ((first & 0xe0) === 0xc0) {
      code = ((first & 0x1f) << 6) | (bytes[offset++] & 0x3f)
    } else if ((first & 0xf0) === 0xe0) {
      code = ((first & 0x0f) << 12) | ((bytes[offset++] & 0x3f) << 6) | (bytes[offset++] & 0x3f)
    } else {
      code = ((first & 0x07) << 18) | ((bytes[offset++] & 0x3f) << 12)
        | ((bytes[offset++] & 0x3f) << 6) | (bytes[offset++] & 0x3f)
    }

    if (code <= 0xffff) {
      result += String.fromCharCode(code)
    } else {
      code -= 0x10000
      result += String.fromCharCode(0xd800 + (code >> 10), 0xdc00 + (code & 0x3ff))
    }
  }
  return result
}

function workspaceName(id) {
  return "herdr:" + encode(id)
}

function appId(id) {
  return "herdr-pane-" + encode(id)
}
