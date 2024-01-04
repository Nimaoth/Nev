import std/[options]
import misc/[util, custom_async, custom_logger]

logCategory "clipboard"

when defined(js):
  import std/[jsffi, dom]

  type Clipboard = ref object of JsObject

  proc hasClipboard(): bool {.importjs: "!!navigator.clipboard@".}
  proc getClipboard(): Clipboard {.importjs: "navigator.clipboard@".}
  proc readText(clipboard: Clipboard): Future[cstring] {.importjs: "#.readText()".}
  proc writeText(clipboard: Clipboard, str: cstring): Future[void] {.importjs: "#.writeText(@)".}

  proc setSystemClipboardText*(str: string) =
    if not hasClipboard():
      log lvlError, "Clipboard not available"
      return
    asyncCheck getClipboard().writeText(str.cstring)

  proc getSystemClipboardText*(): Future[Option[string]] {.async.} =
    if not hasClipboard():
      log lvlError, "Clipboard not available"
      return string.none
    return some $getClipboard().readText().await

else:
  import nimclipboard/libclipboard

  var clipboard = clipboardNew(nil)

  proc setSystemClipboardText*(str: string) =
    clipboard.clipboardClear(LCB_CLIPBOARD)
    discard clipboard.clipboardSetText(str.cstring)

  proc getSystemClipboardText*(): Future[Option[string]] {.async.} =
    return some $clipboard.clipboardText()

