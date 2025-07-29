import std/[options]
import misc/[util, custom_async, custom_logger]

logCategory "clipboard"

import compilation_config

when enableSystemClipboard:
  static:
    echo "Building with system clipboard"
  import nimclipboard/libclipboard
  import system/ansi_c

  var clipboard = clipboardNew(nil)

  proc setSystemClipboardText*(str: string) =
    clipboard.clipboardClear(LCB_CLIPBOARD)
    discard clipboard.clipboardSetText(str.cstring)

  proc getClipboardThread(): Option[string] {.gcsafe.} =
    try:
      proc findCr(str: cstring, start: int, len: int): int =
        let i = str.toOpenArray(0, len - 1).find('\r', start)
        if i == -1:
          return len
        return i

      var len: cint = 0
      let resRaw = clipboard.clipboardTextEx(len.addr, LCB_CLIPBOARD)

      var res = newStringOfCap(len.int)
      var lastI = 0
      var i = resRaw.findCr(0, len.int)
      while lastI < len.int:
        if i > lastI:
          let start = res.len
          let amount = i - lastI
          res.setLen(res.len + amount)
          copyMem(res[start].addr, resRaw[lastI].addr, amount)
        lastI = i + 1
        i = resRaw.findCr(lastI, len.int)

      c_free(resRaw)
      return res.some
    except CatchableError:
      return string.none

  proc getSystemClipboardText*(): Future[Option[string]] {.async.} =
    return spawnAsync(getClipboardThread).await

  proc destroyClipboard*() =
    if clipboard != nil:
      clipboard.clipboardFree()

else:
  static:
    echo "Building without system clipboard"
  proc setSystemClipboardText*(str: string) =
    discard

  proc getSystemClipboardText*(): Future[Option[string]] {.async.} =
    return string.none

  proc destroyClipboard*() =
    discard
