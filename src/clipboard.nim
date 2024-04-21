import std/[options]
import misc/[util, custom_async, custom_logger]

logCategory "clipboard"

when defined(js):
  import std/[jsffi]

  type Clipboard = ref object of JsObject

  proc hasClipboard(): bool {.importjs: "!!navigator.clipboard@".}
  proc hasClipboardWriteText(): bool {.importjs: "!!navigator.clipboard.writeText@".}
  proc hasClipboardReadText(): bool {.importjs: "!!navigator.clipboard.readText@".}
  proc getClipboard(): Clipboard {.importjs: "navigator.clipboard@".}
  proc readText(clipboard: Clipboard): Future[cstring] {.importjs: "#.readText()".}
  proc writeText(clipboard: Clipboard, str: cstring): Future[void] {.importjs: "#.writeText(@)".}

  proc setSystemClipboardText*(str: string) =
    if not hasClipboard() or not hasClipboardWriteText():
      log lvlError, "Clipboard set text not available"
      return
    asyncCheck getClipboard().writeText(str.cstring)

  proc getSystemClipboardText*(): Future[Option[string]] {.async.} =
    if not hasClipboard() or not hasClipboardReadText():
      log lvlError, "Clipboard get text not available"
      return string.none
    return some $getClipboard().readText().await

else:
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
