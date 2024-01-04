import std/[options]

when defined(js):
  proc setSystemClipboardText*(str: string) =
    discard

  proc getSystemClipboardText*(): Option[string] =
    return string.none

else:
  import nimclipboard/libclipboard

  var clipboard = clipboardNew(nil)

  proc setSystemClipboardText*(str: string) =
    clipboard.clipboardClear(LCB_CLIPBOARD)
    discard clipboard.clipboardSetText(str.cstring)

  proc getSystemClipboardText*(): Option[string] =
    return some $clipboard.clipboardText()

