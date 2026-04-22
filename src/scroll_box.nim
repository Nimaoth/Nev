import std/[options, strformat]
import pixie, chroma
import results
import misc/[util, render_command]

type
  ScrollBox* = object
    size*: Vec2
    sizeFlags*: UINodeFlags
    index*: int
    pivot*: float = 0
    offset*: Vec2
    scrollIntoView: bool = false
    snapIntoView: bool = false
    scrollCenter: bool = false

    enableScrolling*: bool = true
    smoothScroll*: bool = true
    scrollMomentum*: Vec2 = vec2(0)
    scrollSpeed*: float = 20
    margin*: float = 100
    extra*: float = 0
    maxIndex*: int = 0
    defaultItemHeight*: float = 1

    items*: seq[tuple[index: int, bounds: bumpy.Rect]]
    up*: bool

    currentIndex*: int
    currentOffset*: Vec2
    currentItemBounds*: bumpy.Rect

    scrollHandleShrinkFactor*: float = 15

proc itemHeight*(sv: ScrollBox, index: int): float =
  if sv.items.len > 0:
    if index < sv.items[0].index:
      return sv.defaultItemHeight
    if index > sv.items[^1].index:
      return sv.defaultItemHeight
    let i = index - sv.items[0].index
    if i in 0..sv.items.high and sv.items[i].index == index:
      return sv.items[i].bounds.h

    # Fallback, shouldn't really happen
    for item in sv.items:
      if item.index == index:
        return item.bounds.h
  sv.defaultItemHeight

proc getFirstItemOffset*(sv: ScrollBox): float =
  if sv.items.len == 0:
    return 0
  let topItemIndex = sv.items[0].index
  if topItemIndex == 0:
    return sv.items[0].bounds.y
  return sv.items[0].bounds.y - topItemIndex.float * sv.defaultItemHeight

proc getMinFirstItemOffset*(sv: ScrollBox): float =
  if sv.items.len == 0:
    return 0

  let firstIndex = sv.items[0].index
  let lastIndex = sv.items[^1].index

  var totalHeight = 0.0

  let numItemsBefore = firstIndex
  totalHeight += numItemsBefore.float * sv.defaultItemHeight

  totalHeight += sv.items[^1].bounds.yh - sv.items[0].bounds.y

  let numItemsAfter = sv.maxIndex - lastIndex
  totalHeight += numItemsAfter.float * sv.defaultItemHeight

  totalHeight -= sv.margin
  totalHeight -= sv.itemHeight(sv.maxIndex)

  return min(-totalHeight, 0)

proc getScrollOffsetNorm*(sv: ScrollBox): float =
  let min = sv.getMinFirstItemOffset()
  if min == 0:
    return 0
  let curr = sv.getFirstItemOffset()
  return abs(curr / min)

proc getScrollableSize*(sv: ScrollBox): float =
  return sv.getMinFirstItemOffset().abs / sv.defaultItemHeight.max(1)

proc getScrollBarHandleHeightRatio*(sv: ScrollBox): float =
  return sv.scrollHandleShrinkFactor / (sv.getScrollableSize() + sv.scrollHandleShrinkFactor - 1).max(1)

proc clampBottom(sv: var ScrollBox) =
  if sv.items.len == 0:
    return
  let first {.cursor.} = sv.items[0]
  if first.index == 0 and first.bounds.y > 0:
    let offset = first.bounds.y
    sv.offset.y -= offset
    sv.currentOffset.y -= offset
    sv.scrollMomentum.y = 0
    for item in sv.items.mitems:
      item.bounds.y -= offset
    return

proc clampTop(sv: var ScrollBox) =
  if sv.items.len == 0:
    return
  let last {.cursor.} = sv.items[^1]
  if last.index == sv.maxIndex and last.bounds.y < sv.margin:
    let offset = sv.margin - last.bounds.y
    sv.offset.y += offset
    sv.scrollMomentum.y = 0
    for item in sv.items.mitems:
      item.bounds.y += offset
    return

proc clampIndex0Top(sv: var ScrollBox) {.gcsafe, raises: [].} =
  if sv.items.len == 0:
    return
  let first {.cursor.} = sv.items[0]
  if first.index == 0 and first.bounds.y > 0:
    let offset = first.bounds.y
    sv.offset.y -= offset
    sv.currentOffset.y -= offset
    sv.scrollMomentum.y = 0
    for item in sv.items.mitems:
      item.bounds.y -= offset

proc clampScrollYForIndex0(sv: var ScrollBox) {.gcsafe, raises: [].} =
  if sv.items.len > 0:
    var estimatedIndex0Y = sv.offset.y
    var i = sv.index
    while estimatedIndex0Y >= 0 and i > 0:
      dec i
      estimatedIndex0Y -= sv.itemHeight(i)
    if i == 0 and estimatedIndex0Y > 0:
      let offset = estimatedIndex0Y
      sv.offset.y -= offset
      sv.currentOffset.y -= offset
      sv.scrollMomentum.y = 0
  elif sv.index > 0:
    let estimatedIndex0Y = sv.offset.y - sv.index.float * sv.defaultItemHeight
    if estimatedIndex0Y > 0:
      let offset = estimatedIndex0Y
      sv.offset.y -= offset
      sv.currentOffset.y -= offset
      sv.scrollMomentum.y = 0

proc clampLeft(sv: var ScrollBox) =
  sv.offset.x = min(sv.offset.x, 0.0)
  if sv.offset.x == 0.0 and sv.scrollMomentum.x > 0.0:
    sv.scrollMomentum.x = 0

proc clamp*(sv: var ScrollBox, maxIndex: int) =
  if sv.items.len == 0:
    return
  let first {.cursor.} = sv.items[0]
  if first.index == 0 and first.bounds.y >= 0:
    let offset = first.bounds.y
    sv.offset.y -= offset
    sv.scrollMomentum.y = 0
    for item in sv.items.mitems:
      item.bounds.y -= offset
    return

  let last = sv.items[^1]
  if last.index == maxIndex and last.bounds.y < sv.margin:
    let offset = sv.margin - last.bounds.y
    sv.offset.y += offset
    sv.scrollMomentum.y = 0
    for item in sv.items.mitems:
      item.bounds.y += offset
    return

  sv.clampIndex0Top()
  sv.clampScrollYForIndex0()

proc scroll*(sv: var ScrollBox, offset: Vec2) =
  if offset != vec2(0):
    sv.offset += offset
    sv.currentOffset += offset
    sv.clampLeft()
    sv.clampIndex0Top()
    sv.clampScrollYForIndex0()

proc scroll*(sv: var ScrollBox, y: float) =
  sv.scroll(vec2(0, y))

proc updateScroll*(sv: var ScrollBox, dt: float) =
  if sv.smoothScroll:
    let delta = sv.scrollMomentum * min(dt * sv.scrollSpeed, 1)
    sv.offset += delta
    sv.currentOffset += delta
    sv.scrollMomentum -= delta
    sv.clampIndex0Top()
    sv.clampScrollYForIndex0()

  sv.clampLeft()

proc scrollWithMomentum*(sv: var ScrollBox, offset: Vec2) =
  if sv.smoothScroll:
    sv.scrollMomentum += offset
    if sv.offset.x == 0.0 and sv.scrollMomentum.x > 0.0:
      sv.scrollMomentum.x = 0
  else:
    sv.offset += offset
    sv.currentOffset += offset
    sv.clampLeft()
    sv.clampIndex0Top()
    sv.clampScrollYForIndex0()

proc scrollWithMomentum*(sv: var ScrollBox, y: float) =
  sv.scrollWithMomentum(vec2(0, y))

proc scrollToX*(sv: var ScrollBox, x: float) =
  ## Scroll so the given x position is visible, `margin` distance from left/right borders
  let targetX = -(x - sv.margin)
  let clamped = min(targetX, 0.0)
  sv.scrollWithMomentum(vec2(clamped - sv.offset.x, 0))

proc beginRender*(sv: var ScrollBox, size: Vec2, sizeFlags: UINodeFlags, maxIndex: int) =
  sv.size = size
  sv.maxIndex = maxIndex
  sv.sizeFlags = sizeFlags
  sv.currentIndex = sv.index
  sv.currentOffset = sv.offset
  sv.up = false
  sv.items.setLen(0)

proc postItemRendered(sv: var ScrollBox, itemSize: Option[Vec2]): bool =
  if itemSize.isNone:
    if sv.up:
      return false
    else:
      sv.up = true
      sv.currentIndex = sv.index - 1
      sv.currentOffset = sv.offset
      sv.clampTop()
      return true

  if sv.up:
    sv.currentIndex -= 1
    sv.currentOffset.y -= itemSize.get.y
    sv.currentItemBounds = rect(vec2(sv.currentOffset.x, sv.currentOffset.y), itemSize.get)
    sv.items.insert (sv.currentIndex + 1, sv.currentItemBounds)

  else:
    if sv.items.len == 0:
      # Handle scrolling after rendering the first item
      let pivotOffset = -sv.pivot * itemSize.get.y
      sv.pivot = 0
      sv.offset.y += pivotOffset
      if sv.snapIntoView:
        sv.scrollMomentum = vec2(0)
        if sv.scrollCenter:
          let targetOffset = sv.size.y * 0.5 - itemSize.get.y * 0.5
          sv.scroll(targetOffset - sv.offset.y)
        elif sv.offset.y < sv.margin:
          sv.scroll(itemSize.get.y)
        else:
          sv.scroll(-itemSize.get.y)
        sv.snapIntoView = false
        sv.scrollIntoView = false
        sv.scrollCenter = false
      elif sv.scrollIntoView:
        sv.scrollMomentum = vec2(0)
        if sv.scrollCenter:
          let targetOffset = sv.size.y * 0.5 - itemSize.get.y * 0.5
          sv.scrollWithMomentum(targetOffset - sv.offset.y)
        elif sv.offset.y < sv.margin:
          sv.scrollWithMomentum(itemSize.get.y)
        else:
          sv.scrollWithMomentum(-itemSize.get.y)
        sv.snapIntoView = false
        sv.scrollIntoView = false
        sv.scrollCenter = false
      sv.currentOffset.y += pivotOffset

    sv.currentItemBounds = rect(vec2(sv.currentOffset.x, sv.currentOffset.y), itemSize.get)
    sv.items.add (sv.currentIndex, sv.currentItemBounds)
    sv.currentIndex += 1
    sv.currentOffset.y += itemSize.get.y
    if SizeToContentX in sv.sizeFlags:
      sv.size.x = max(sv.size.x, itemSize.get.x)

    if sv.items.len == 1:
      sv.clampBottom()

    if SizeToContentY notin sv.sizeFlags:
      if sv.currentOffset.y >= sv.size.y + sv.extra:
        sv.clampTop()
        sv.up = true
        sv.currentIndex = sv.index - 1
        sv.currentOffset = sv.offset

  return true

template renderItemT*(sv: var ScrollBox, body: untyped): bool =
  block:
    if sv.up and sv.currentOffset.y <= -sv.extra:
      # Going up and offscreen, we're done
      false
    else:
      let itemSize = body
      sv.postItemRendered(itemSize)

proc renderItem*(sv: var ScrollBox, cb: proc(sv: ScrollBox, index: int): Option[Vec2] {.raises: [].}): bool =
  sv.renderItemT:
    cb(sv, sv.currentIndex)

proc endRender*(sv: var ScrollBox) =
  if sv.items.len > 0:
    sv.index = sv.items[0].index
    sv.offset.y = sv.items[0].bounds.y
    for i in 0..sv.items.high:
      if sv.items[i].bounds.y > 0:
        break
      sv.index = sv.items[i].index
      sv.offset.y = sv.items[i].bounds.y

    sv.clampLeft()
    sv.clampIndex0Top()
    sv.clampScrollYForIndex0()
    sv.offset.x = sv.items[0].bounds.x

proc itemBounds*(sv: var ScrollBox, index: int): Option[bumpy.Rect] =
  for item in sv.items:
    if item.index == index:
      return item.bounds.some
  return bumpy.Rect.none

proc itemIndex*(sv: var ScrollBox, index: int): Option[int] =
  for item in sv.items:
    if item.index == index:
      return item.index.some
  return int.none

proc scrollToY*(sv: var ScrollBox, index: int, y: float) =
  if sv.itemBounds(index).getSome(b) and b.y == y:
    return
  sv.index = index
  sv.offset.y = y
  sv.clampIndex0Top()
  sv.clampScrollYForIndex0()

proc scrollTo*(sv: var ScrollBox, index: int, center: bool = false, centerOffscreen: bool = false, snap: bool = false) =
  for v in sv.items:
    if v.index == index:
      if center:
        let targetOffset = sv.size.y * 0.5 - v.bounds.h * 0.5
        sv.pivot = 0
        sv.index = v.index
        sv.offset.y = v.bounds.y
        sv.scrollMomentum = vec2(0)
        if snap:
          sv.snapIntoView = true
        else:
          sv.scrollIntoView = false
        sv.scrollCenter = false
        sv.scrollWithMomentum(targetOffset - v.bounds.y)
      elif v.bounds.y < sv.margin:
        sv.scrollMomentum = vec2(0)
        if snap:
          sv.snapIntoView = true
        else:
          sv.scrollIntoView = false
        sv.scrollCenter = false
        sv.scrollWithMomentum(sv.margin - v.bounds.y)
      elif v.bounds.yh >= sv.size.y - sv.margin:
        sv.scrollMomentum = vec2(0)
        if snap:
          sv.snapIntoView = true
        else:
          sv.scrollIntoView = false
        sv.scrollCenter = false
        var targetY = sv.size.y - sv.margin - v.bounds.h
        targetY = max(targetY, sv.margin)
        let offset = targetY - v.bounds.y
        sv.scrollWithMomentum(offset)
      return

  let firstIndex = if sv.items.len == 0: -1 else: sv.items[0].index
  let lastIndex = if sv.items.len == 0: -1 else: sv.items[^1].index
  if index < firstIndex:
    sv.index = index
    sv.offset.y = sv.margin
    sv.pivot = 1
    if snap:
      sv.snapIntoView = true
    else:
      sv.scrollIntoView = true
    sv.scrollCenter = center or centerOffscreen
    sv.clampIndex0Top()
    sv.clampScrollYForIndex0()
  elif index > lastIndex:
    let itemHeight = if sv.defaultItemHeight > 0: sv.defaultItemHeight
      elif sv.items.len > 0: sv.items[^1].bounds.h
      else: 0

    if itemHeight > 0 and sv.items.len > 0:
      let lastItem = sv.items[^1]
      let estimatedY = lastItem.bounds.yh + (index - lastIndex - 1).float * itemHeight
      let estimatedBottom = estimatedY + itemHeight

      if estimatedBottom <= sv.size.y - sv.margin:
        return

    sv.index = index
    sv.offset.y = sv.size.y - sv.margin
    sv.pivot = 0
    if snap:
      sv.snapIntoView = true
    else:
      sv.scrollIntoView = true
    sv.scrollCenter = center or centerOffscreen
