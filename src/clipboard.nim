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
      var len: cint = 0
      let resRaw = clipboard.clipboardTextEx(len.addr, LCB_CLIPBOARD)
      let res = $resRaw
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
