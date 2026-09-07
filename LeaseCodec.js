.pragma library

var HOME_BASE = 1000000000
var HOME_SPAN = 500000000
var PARKING_BASE = 2000000000
var PARKING_SPAN = 100000000

function stableName(homeId, encodedSpaceId) {
  return "herdr:v1:" + homeId + ":" + encodedSpaceId
}

function leasedName(homeId, encodedSpaceId, slotId, encodedOriginalName, parkingId) {
  return stableName(homeId, encodedSpaceId)
    + ":leased:" + slotId + ":" + encodedOriginalName + ":" + parkingId
}

function parkedName(slotId, encodedOriginalName, parkingId) {
  return "hypr-herdr:v1:parked:" + slotId + ":" + encodedOriginalName + ":" + parkingId
}

function parseHerdr(name) {
  var parts = String(name || "").split(":")
  if (parts.length !== 4 && parts.length !== 8) return null
  if (parts[0] !== "herdr" || parts[1] !== "v1") return null

  var homeId = Number(parts[2])
  if (!Number.isInteger(homeId) || homeId <= 10) return null
  if (!isEncoded(parts[3])) return null

  var result = {
    homeId: homeId,
    encodedSpaceId: parts[3],
    leased: false,
    slotId: 0,
    encodedOriginalName: "",
    parkingId: 0
  }
  if (parts.length === 4) return result
  if (parts[4] !== "leased") return null

  result.slotId = Number(parts[5])
  result.encodedOriginalName = parts[6]
  result.parkingId = Number(parts[7])
  if (!isEncoded(result.encodedOriginalName)) return null
  if (!Number.isInteger(result.slotId) || result.slotId < 1 || result.slotId > 2147483647) return null
  if (!Number.isInteger(result.parkingId) || result.parkingId <= 10) return null
  result.leased = true
  return result
}

function parseParked(name) {
  var parts = String(name || "").split(":")
  if (parts.length !== 6) return null
  if (parts[0] !== "hypr-herdr" || parts[1] !== "v1" || parts[2] !== "parked") return null

  var slotId = Number(parts[3])
  var parkingId = Number(parts[5])
  if (!isEncoded(parts[4])) return null
  if (!Number.isInteger(slotId) || slotId < 1 || slotId > 2147483647) return null
  if (!Number.isInteger(parkingId) || parkingId <= 10) return null
  return {
    slotId: slotId,
    encodedOriginalName: parts[4],
    parkingId: parkingId
  }
}

function isEncoded(value) {
  return typeof value === "string" && value.length > 0 && /^[A-Za-z0-9_-]+$/.test(value)
}

function hash(value) {
  var text = String(value)
  var result = 2166136261
  for (var i = 0; i < text.length; i++) {
    result ^= text.charCodeAt(i)
    result = Math.imul(result, 16777619)
  }
  return result >>> 0
}

function homeCandidate(spaceId, attempt) {
  return HOME_BASE + ((hash(spaceId) + Number(attempt || 0)) % HOME_SPAN)
}

function parkingCandidate(slotId, attempt) {
  return PARKING_BASE + ((Number(slotId) * 4099 + Number(attempt || 0)) % PARKING_SPAN)
}
