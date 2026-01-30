import std/[options]
import pixie, chroma
import results
import misc/[util, render_command]

type
  ScrollBox* = object
    size*: Vec2
    sizeFlags*: UINodeFlags
    index*: int
    pivot*: float = 0
    offset*: float
    scrollIntoView: bool = false
    snapIntoView: bool = false
    scrollCenter: bool = false

    enableScrolling*: bool = true
    smoothScroll*: bool = true
    scrollMomentum*: float = 0
    scrollSpeed*: float = 20
    margin*: float = 100
    extra*: float = 0
    maxIndex*: int = 0

    items*: seq[tuple[index: int, bounds: bumpy.Rect]]
    up*: bool

    currentIndex*: int
    currentOffset*: float
    currentItemBounds*: bumpy.Rect

proc clampBottom(sv: var ScrollBox) =
  if sv.items.len == 0:
    return
  let first = sv.items[0]
  if first.index == 0 and first.bounds.yh > sv.size.y - sv.margin:
    let offset = first.bounds.yh - (sv.size.y - sv.margin)
    sv.offset -= offset
    sv.currentOffset -= offset
    sv.scrollMomentum = 0
    for item in sv.items.mitems:
      item.bounds.y -= offset
    return

proc clampTop(sv: var ScrollBox) =
  if sv.items.len == 0:
    return
  let last = sv.items[^1]
  if last.index == sv.maxIndex and last.bounds.y < sv.margin:
    let offset = sv.margin - last.bounds.y
    sv.offset += offset
    sv.scrollMomentum = 0
    for item in sv.items.mitems:
      item.bounds.y += offset
    return

proc clamp*(sv: var ScrollBox, maxIndex: int) =
  if sv.items.len == 0:
    return
  let first = sv.items[0]
  if first.index == 0 and first.bounds.yh > sv.size.y - sv.margin:
    let offset = first.bounds.yh - (sv.size.y - sv.margin)
    sv.offset -= offset
    sv.scrollMomentum = 0
    for item in sv.items.mitems:
      item.bounds.y -= offset
    return

  let last = sv.items[^1]
  if last.index == maxIndex and last.bounds.y < sv.margin:
    let offset = sv.margin - last.bounds.y
    sv.offset += offset
    sv.scrollMomentum = 0
    for item in sv.items.mitems:
      item.bounds.y += offset
    return

proc scroll*(sv: var ScrollBox, offset: float) =
  if offset != 0:
    sv.offset += offset
    sv.currentOffset += offset

proc updateScroll*(sv: var ScrollBox, dt: float) =
  if sv.smoothScroll:
    let delta = sv.scrollMomentum * min(dt * sv.scrollSpeed, 1)
    sv.offset += delta
    sv.currentOffset += delta
    sv.scrollMomentum -= delta

proc scrollWithMomentum*(sv: var ScrollBox, offset: float) =
  if sv.smoothScroll:
    sv.scrollMomentum += offset
  else:
    sv.offset += offset
    sv.currentOffset += offset

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
    sv.currentOffset -= itemSize.get.y
    sv.currentItemBounds = rect(vec2(0, sv.currentOffset), itemSize.get)
    sv.items.insert (sv.currentIndex + 1, sv.currentItemBounds)

  else:
    if sv.items.len == 0:
      # Handle scrolling after rendering the first item
      let pivotOffset = -sv.pivot * itemSize.get.y
      sv.pivot = 0
      sv.offset += pivotOffset
      if sv.snapIntoView:
        sv.scrollMomentum = 0
        if sv.scrollCenter:
          let targetOffset = sv.size.y * 0.5 - itemSize.get.y * 0.5
          sv.scroll(targetOffset - sv.offset)
        elif sv.offset < sv.margin:
          sv.scroll(itemSize.get.y)
        else:
          sv.scroll(-itemSize.get.y)
        sv.snapIntoView = false
        sv.scrollIntoView = false
        sv.scrollCenter = false
      elif sv.scrollIntoView:
        sv.scrollMomentum = 0
        if sv.scrollCenter:
          let targetOffset = sv.size.y * 0.5 - itemSize.get.y * 0.5
          sv.scrollWithMomentum(targetOffset - sv.offset)
        elif sv.offset < sv.margin:
          sv.scrollWithMomentum(itemSize.get.y)
        else:
          sv.scrollWithMomentum(-itemSize.get.y)
        sv.snapIntoView = false
        sv.scrollIntoView = false
        sv.scrollCenter = false
      sv.currentOffset += pivotOffset

    sv.currentItemBounds = rect(vec2(0, sv.currentOffset), itemSize.get)
    sv.items.add (sv.currentIndex, sv.currentItemBounds)
    sv.currentIndex += 1
    sv.currentOffset += itemSize.get.y
    if SizeToContentX in sv.sizeFlags:
      sv.size.x = max(sv.size.x, itemSize.get.x)

    if sv.items.len == 1:
      sv.clampBottom()

    if SizeToContentY notin sv.sizeFlags:
      if sv.currentOffset >= sv.size.y + sv.extra:
        sv.clampTop()
        sv.up = true
        sv.currentIndex = sv.index - 1
        sv.currentOffset = sv.offset

  return true

template renderItemT*(sv: var ScrollBox, body: untyped): bool =
  block:
    if sv.up and sv.currentOffset <= -sv.extra:
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
    sv.offset = sv.items[0].bounds.y
    for i in 0..sv.items.high:
      if sv.items[i].bounds.y > 0:
        break
      sv.index = sv.items[i].index
      sv.offset = sv.items[i].bounds.y

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

proc scrollXToY*(sv: var ScrollBox, index: int, y: float) =
  if sv.itemBounds(index).getSome(b) and b.y == y:
    # Item is already it the correct location
    return
  sv.index = index
  sv.offset = y

proc scrollTo*(sv: var ScrollBox, index: int, center: bool = false, centerOffscreen: bool = false, snap: bool = false) =
  for v in sv.items:
    if v.index == index:
      if center:
        let targetOffset = sv.size.y * 0.5 - v.bounds.h * 0.5
        sv.pivot = 0
        sv.index = v.index
        sv.offset = v.bounds.y
        sv.scrollMomentum = 0
        if snap:
          sv.snapIntoView = true
        else:
          sv.scrollIntoView = false
        sv.scrollCenter = false
        sv.scrollWithMomentum(targetOffset - v.bounds.y)
      elif v.bounds.y < sv.margin:
        sv.scrollMomentum = 0
        if snap:
          sv.snapIntoView = true
        else:
          sv.scrollIntoView = false
        sv.scrollCenter = false
        sv.scrollWithMomentum(sv.margin - v.bounds.y)
      elif v.bounds.yh >= sv.size.y - sv.margin:
        sv.scrollMomentum = 0
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
    sv.offset = sv.margin
    sv.pivot = 1
    if snap:
      sv.snapIntoView = true
    else:
      sv.scrollIntoView = true
    sv.scrollCenter = center or centerOffscreen
  elif index > lastIndex:
    sv.index = index
    sv.offset = sv.size.y - sv.margin
    sv.pivot = 0
    if snap:
      sv.snapIntoView = true
    else:
      sv.scrollIntoView = true
    sv.scrollCenter = center or centerOffscreen
