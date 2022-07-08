import winim/lean
import std/unicode

proc getMonitorRect*(monitor: int = 0): tuple[left, right, top, bottom: int] =
  type MonitorSizeHelper = object
    index: int
    targetIndex: int
    rect: windef.RECT

  proc enumMonitor(monitor: HMONITOR, hdc: HDC, rect: LPRECT, data: LPARAM): WINBOOL {.stdcall.} =
    let helper = cast[ptr MonitorSizeHelper](data)
    if helper.index == helper.targetIndex:
      helper.rect = rect[]
      return 0

    inc helper.index
    return 1

  var helper = MonitorSizeHelper(index: 0, targetIndex: monitor, rect: windef.RECT(left: 0, right: 1920, top: 0, bottom: 1080))
  EnumDisplayMonitors(0, nil, enumMonitor, cast[LPARAM](addr helper))

  return (left: int(helper.rect.left), right: int(helper.rect.right), top: int(helper.rect.top), bottom: int(helper.rect.bottom))

proc isNextMsgChar*(): bool =
  var msg: MSG = MSG.default
  if PeekMessage(addr msg, 0, 0, 0, PM_NOREMOVE) == 0:
    return false

  case msg.message
  of WM_CHAR, WM_SYSCHAR, WM_UNICHAR: discard
  else: return false

  if msg.message == WM_UNICHAR and msg.wParam == UNICODE_NOCHAR:
    return false;

  let codepoint = msg.wParam.uint32
  let rune = Rune(codepoint)

  if rune.uint32 < 32 or (rune.uint32 > 126 and rune.uint32 < 160):
    return false

  return true
