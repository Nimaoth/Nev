import std/[options, macros]
import misc/[util, custom_async, custom_logger]

logCategory "clipboard"

import compilation_config

when enableWindyClipboard:
  import windy
  static:
    hint("Building with windy clipboard")

  proc setSystemClipboardText*(str: string) =
    {.gcsafe.}:
      setClipboardString(str)

  proc getSystemClipboardText*(): Future[Option[string]] {.async.} =
    {.gcsafe.}:
      return getClipboardString().some

else:
  static:
    echo "Building without system clipboard"
  proc setSystemClipboardText*(str: string) =
    discard

  proc getSystemClipboardText*(): Future[Option[string]] {.async.} =
    return string.none

  proc destroyClipboard*() =
    discard
