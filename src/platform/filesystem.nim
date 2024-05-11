{.used.}

import std/[strutils, os]

import misc/[custom_async, array_buffer]

type FileSystem* = ref object of RootObj
  discard

method init*(self: FileSystem, appDir: string) {.base.} = discard

method loadFile*(self: FileSystem, path: string): string {.base.} = discard
method loadFileAsync*(self: FileSystem, name: string): Future[string] {.base.} = discard
method loadFileBinaryAsync*(self: FileSystem, name: string): Future[ArrayBuffer] {.base.} = discard

method saveFile*(self: FileSystem, path: string, content: string) {.base.} = discard

method getApplicationFilePath*(self: FileSystem, name: string): string {.base.} = discard
method loadApplicationFile*(self: FileSystem, name: string): string {.base.} = discard
method saveApplicationFile*(self: FileSystem, name: string, content: string) {.base.} = discard

when defined(js):
  import filesystem_browser
  let fs*: FileSystem = new FileSystemBrowser

else:
  import filesystem_desktop
  let fs*: FileSystem = new FileSystemDesktop
  fs.init getAppDir()

proc normalizePathUnix*(path: string): string =
  var stripLeading = false
  if path.startsWith("/") and path.len >= 3 and path[2] == ':':
    # Windows path: /C:/...
    stripLeading = true
  result = path.normalizedPath.replace('\\', '/').strip(leading=stripLeading, chars={'/'})
  if result.len >= 2 and result[1] == ':':
    result[0] = result[0].toUpperAscii

proc `//`*(a: string, b: string): string = (a / b).normalizePathUnix
