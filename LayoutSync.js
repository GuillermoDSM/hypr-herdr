.pragma library

function number(value) {
  var parsed = Number(value)
  return isFinite(parsed) ? parsed : 0
}

function rect(value) {
  value = value || {}
  return {
    x: number(value.x),
    y: number(value.y),
    width: Math.max(0, number(value.width)),
    height: Math.max(0, number(value.height))
  }
}

function right(value) { return value.x + value.width }
function bottom(value) { return value.y + value.height }

function same(a, b, tolerance) {
  return Math.abs(a.x - b.x) <= tolerance
    && Math.abs(a.y - b.y) <= tolerance
    && Math.abs(a.width - b.width) <= tolerance
    && Math.abs(a.height - b.height) <= tolerance
}

function bounds(leaves) {
  var x1 = Infinity
  var y1 = Infinity
  var x2 = -Infinity
  var y2 = -Infinity
  for (var i = 0; i < leaves.length; i++) {
    x1 = Math.min(x1, leaves[i].rect.x)
    y1 = Math.min(y1, leaves[i].rect.y)
    x2 = Math.max(x2, right(leaves[i].rect))
    y2 = Math.max(y2, bottom(leaves[i].rect))
  }
  return { x: x1, y: y1, width: x2 - x1, height: y2 - y1 }
}

function directChildren(region, direction, panes, splits, currentSplit) {
  var candidates = []
  for (var i = 0; i < panes.length; i++)
    candidates.push({ kind: "leaf", paneId: panes[i].paneId, rect: panes[i].rect })
  for (var j = 0; j < splits.length; j++) {
    if (splits[j] !== currentSplit)
      candidates.push({ kind: "split", split: splits[j], rect: splits[j].rect })
  }

  var first = []
  var second = []
  for (var index = 0; index < candidates.length; index++) {
    var candidate = candidates[index]
    if (direction === "right") {
      if (Math.abs(candidate.rect.x - region.x) <= 1
          && Math.abs(candidate.rect.y - region.y) <= 1
          && Math.abs(candidate.rect.height - region.height) <= 1
          && candidate.rect.width < region.width - 1) first.push(candidate)
      if (Math.abs(right(candidate.rect) - right(region)) <= 1
          && Math.abs(candidate.rect.y - region.y) <= 1
          && Math.abs(candidate.rect.height - region.height) <= 1
          && candidate.rect.width < region.width - 1) second.push(candidate)
    } else {
      if (Math.abs(candidate.rect.y - region.y) <= 1
          && Math.abs(candidate.rect.x - region.x) <= 1
          && Math.abs(candidate.rect.width - region.width) <= 1
          && candidate.rect.height < region.height - 1) first.push(candidate)
      if (Math.abs(bottom(candidate.rect) - bottom(region)) <= 1
          && Math.abs(candidate.rect.x - region.x) <= 1
          && Math.abs(candidate.rect.width - region.width) <= 1
          && candidate.rect.height < region.height - 1) second.push(candidate)
    }
  }

  function largest(items) {
    items.sort(function(a, b) {
      return b.rect.width * b.rect.height - a.rect.width * a.rect.height
    })
    return items.length > 0 ? items[0] : null
  }
  return [largest(first), largest(second)]
}

function herdrNodeFor(candidate, panes, splits, path, seen) {
  if (!candidate) return { error: "layout child is missing" }
  if (candidate.kind === "leaf")
    return { kind: "leaf", paneId: candidate.paneId, rect: candidate.rect }

  var split = candidate.split
  if (seen[split.id]) return { error: "layout split cycle" }
  seen[split.id] = true
  var children = directChildren(split.rect, split.direction, panes, splits, split)
  var first = herdrNodeFor(children[0], panes, splits, path.concat([0]), seen)
  var second = herdrNodeFor(children[1], panes, splits, path.concat([1]), seen)
  if (first.error) return first
  if (second.error) return second
  return {
    kind: "split",
    direction: split.direction,
    ratio: split.ratio,
    path: path,
    first: first,
    second: second,
    rect: split.rect
  }
}

function buildHerdrTree(layout) {
  if (!layout || !Array.isArray(layout.panes) || layout.panes.length === 0)
    return { error: "Herdr layout has no panes" }

  var panes = []
  for (var i = 0; i < layout.panes.length; i++) {
    panes.push({
      paneId: String(layout.panes[i].pane_id || ""),
      rect: rect(layout.panes[i].rect)
    })
  }
  if (panes.length === 1)
    return { tree: { kind: "leaf", paneId: panes[0].paneId, rect: panes[0].rect } }

  var splits = []
  var rawSplits = Array.isArray(layout.splits) ? layout.splits : []
  for (var j = 0; j < rawSplits.length; j++) {
    splits.push({
      id: String(rawSplits[j].id || ("split-" + j)),
      direction: String(rawSplits[j].direction || ""),
      ratio: number(rawSplits[j].ratio),
      rect: rect(rawSplits[j].rect)
    })
  }
  var area = rect(layout.area)
  var root = null
  for (var splitIndex = 0; splitIndex < splits.length; splitIndex++) {
    if (same(splits[splitIndex].rect, area, 1)) {
      root = splits[splitIndex]
      break
    }
  }
  if (!root) return { error: "Herdr layout root is missing" }
  var tree = herdrNodeFor({ kind: "split", split: root }, panes, splits, [], {})
  return tree.error ? tree : { tree: tree }
}

function partitionCandidate(leaves, axis, splitIndex) {
  var ordered = leaves.slice().sort(function(a, b) {
    var ac = axis === "x" ? a.rect.x + a.rect.width / 2 : a.rect.y + a.rect.height / 2
    var bc = axis === "x" ? b.rect.x + b.rect.width / 2 : b.rect.y + b.rect.height / 2
    return ac - bc
  })
  var first = ordered.slice(0, splitIndex)
  var second = ordered.slice(splitIndex)
  var firstBounds = bounds(first)
  var secondBounds = bounds(second)
  var allBounds = bounds(leaves)
  var firstEnd = axis === "x" ? right(firstBounds) : bottom(firstBounds)
  var secondStart = axis === "x" ? secondBounds.x : secondBounds.y
  if (firstEnd > secondStart) return null

  var tolerance = 3
  if (axis === "x") {
    if (Math.abs(firstBounds.y - allBounds.y) > tolerance
        || Math.abs(bottom(firstBounds) - bottom(allBounds)) > tolerance
        || Math.abs(secondBounds.y - allBounds.y) > tolerance
        || Math.abs(bottom(secondBounds) - bottom(allBounds)) > tolerance) return null
  } else if (Math.abs(firstBounds.x - allBounds.x) > tolerance
             || Math.abs(right(firstBounds) - right(allBounds)) > tolerance
             || Math.abs(secondBounds.x - allBounds.x) > tolerance
             || Math.abs(right(secondBounds) - right(allBounds)) > tolerance) return null

  var firstSpan = axis === "x" ? firstBounds.width : firstBounds.height
  var secondSpan = axis === "x" ? secondBounds.width : secondBounds.height
  var gap = Math.max(0, secondStart - firstEnd)
  var total = firstSpan + gap + secondSpan
  return {
    direction: axis === "x" ? "right" : "down",
    ratio: total > 0 ? (firstSpan + gap / 2) / total : 0.5,
    first: first,
    second: second,
    gap: gap
  }
}

function buildGeometryNode(leaves) {
  if (leaves.length === 1)
    return { kind: "leaf", paneId: leaves[0].paneId, rect: leaves[0].rect }

  var candidates = []
  for (var axisIndex = 0; axisIndex < 2; axisIndex++) {
    var axis = axisIndex === 0 ? "x" : "y"
    for (var splitIndex = 1; splitIndex < leaves.length; splitIndex++) {
      var candidate = partitionCandidate(leaves, axis, splitIndex)
      if (candidate) candidates.push(candidate)
    }
  }
  if (candidates.length !== 1)
    return { error: candidates.length === 0 ? "Wayland layout is not a BSP tree" : "Wayland layout tree is ambiguous" }

  var selected = candidates[0]
  var first = buildGeometryNode(selected.first)
  var second = buildGeometryNode(selected.second)
  if (first.error) return first
  if (second.error) return second
  return {
    kind: "split",
    direction: selected.direction,
    ratio: selected.ratio,
    first: first,
    second: second,
    rect: bounds(leaves)
  }
}

function buildGeometryTree(windows) {
  if (!Array.isArray(windows) || windows.length === 0)
    return { error: "Wayland layout has no windows" }
  var leaves = []
  for (var i = 0; i < windows.length; i++) {
    var paneId = String(windows[i].paneId || "")
    var geometry = rect(windows[i].rect)
    if (paneId === "" || geometry.width <= 0 || geometry.height <= 0)
      return { error: "Wayland window geometry is incomplete" }
    leaves.push({ paneId: paneId, rect: geometry })
  }
  var tree = buildGeometryNode(leaves)
  return tree.error ? tree : { tree: tree }
}

function shape(node) {
  if (!node || node.kind === "leaf") return "p"
  return (node.direction === "right" ? "r" : "d")
    + "(" + shape(node.first) + "," + shape(node.second) + ")"
}

function leaves(node, result) {
  result = result || []
  if (node.kind === "leaf") result.push(node.paneId)
  else {
    leaves(node.first, result)
    leaves(node.second, result)
  }
  return result
}

function collectPairs(herdr, wayland, result) {
  if (herdr.kind === "leaf") return
  var targetPaneId = herdr.first.kind === "leaf" ? herdr.first.paneId
    : (herdr.second.kind === "leaf" ? herdr.second.paneId : "")
  result.push({
    path: herdr.path,
    targetPaneId: targetPaneId,
    herdrRatio: herdr.ratio,
    waylandRatio: wayland.ratio,
    direction: herdr.direction
  })
  collectPairs(herdr.first, wayland.first, result)
  collectPairs(herdr.second, wayland.second, result)
}

function analyze(layout, windows) {
  var herdrResult = buildHerdrTree(layout)
  if (herdrResult.error) return { compatible: false, error: herdrResult.error }
  var waylandResult = buildGeometryTree(windows)
  if (waylandResult.error) return { compatible: false, error: waylandResult.error }
  var herdrTree = herdrResult.tree
  var waylandTree = waylandResult.tree
  if (shape(herdrTree) !== shape(waylandTree)) {
    return {
      compatible: false,
      error: "Herdr and Wayland layout trees differ",
      herdrShape: shape(herdrTree),
      waylandShape: shape(waylandTree)
    }
  }

  var desiredLeaves = leaves(herdrTree)
  var currentLeaves = leaves(waylandTree)
  var simulated = currentLeaves.slice()
  var swaps = []
  for (var i = 0; i < desiredLeaves.length; i++) {
    if (simulated[i] === desiredLeaves[i]) continue
    var other = simulated.indexOf(desiredLeaves[i], i + 1)
    if (other < 0) return { compatible: false, error: "pane sets differ" }
    swaps.push({ firstPaneId: simulated[i], secondPaneId: simulated[other] })
    var value = simulated[i]
    simulated[i] = simulated[other]
    simulated[other] = value
  }

  var pairs = []
  collectPairs(herdrTree, waylandTree, pairs)
  var imports = []
  var updates = []
  for (var pairIndex = 0; pairIndex < pairs.length; pairIndex++) {
    var pair = pairs[pairIndex]
    if (pair.targetPaneId === "")
      return { compatible: false, error: "a Wayland split cannot be addressed safely" }
    if (Math.abs(pair.herdrRatio - pair.waylandRatio) > 0.02) {
      imports.push({ paneId: pair.targetPaneId, ratio: pair.herdrRatio, path: pair.path })
      updates.push({ path: pair.path, ratio: pair.waylandRatio })
    }
  }

  return {
    compatible: true,
    swaps: swaps,
    imports: imports,
    updates: updates,
    herdrLeaves: desiredLeaves,
    waylandLeaves: currentLeaves,
    herdrShape: shape(herdrTree),
    waylandShape: shape(waylandTree)
  }
}
