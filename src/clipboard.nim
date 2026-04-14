import std/[options, macros]
import misc/[util, custom_async, custom_logger]

logCategory "clipboard"

import compilation_config

when enableWindyClipboard:
  import platform_service, service
  static:
    hint("Building with windy clipboard")

  proc setSystemClipboardText*(str: string) =
    getServiceChecked(PlatformService).platform.setClipboardText(str)

  proc getSystemClipboardText*(): Future[Option[string]] {.async.} =
    getServiceChecked(PlatformService).platform.getClipboardText().await

else:
  static:
    echo "Building without system clipboard"
  proc setSystemClipboardText*(str: string) =
    discard

  proc getSystemClipboardText*(): Future[Option[string]] {.async.} =
    return string.none

  proc destroyClipboard*() =
    discard
