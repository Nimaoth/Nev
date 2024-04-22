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

const stripLeading = defined(windows)

proc normalizePathUnix*(path: string): string =
  return path.normalizedPath.replace('\\', '/').strip(leading=stripLeading, chars={'/'})

proc `//`*(a: string, b: string): string = (a / b).normalizePathUnix
