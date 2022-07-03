import winim/lean

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