{.used.}

import custom_async

when defined(js):
  import std/[jsffi]
  type ArrayBuffer* = ref object of JsObject
else:
  type ArrayBuffer* = ref object
    buffer*: seq[uint8]

type FileSystem* = ref object of RootObj
  discard

method loadFile*(self: FileSystem, path: string): string {.base.} = discard
method loadFileAsync*(self: FileSystem, name: string): Future[string] {.base.} = discard
method loadFileBinaryAsync*(self: FileSystem, name: string): Future[ArrayBuffer] {.base.} = discard

method saveFile*(self: FileSystem, path: string, content: string) {.base.} = discard

method loadApplicationFile*(self: FileSystem, name: string): string {.base.} = discard
method saveApplicationFile*(self: FileSystem, name: string, content: string) {.base.} = discard

when defined(js):
  import filesystem_browser
  let fs*: FileSystem = new FileSystemBrowser

else:
  import filesystem_desktop
  let fs*: FileSystem = new FileSystemDesktop
