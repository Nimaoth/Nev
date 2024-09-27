{.used.}

import std/[strutils, os]

import misc/[custom_async, array_buffer]

type FileSystem* = ref object of RootObj
  discard

method init*(self: FileSystem, appDir: string) {.base, gcsafe, raises: [].} = discard

method loadFile*(self: FileSystem, path: string): string {.base, gcsafe, raises: [].} = discard
method loadFileAsync*(self: FileSystem, path: string): Future[string] {.base, gcsafe, raises: [].} = discard
method loadFileBinaryAsync*(self: FileSystem, name: string): Future[ArrayBuffer] {.base, gcsafe, raises: [].} = discard

method saveFile*(self: FileSystem, path: string, content: string) {.base, gcsafe, raises: [].} = discard

method getApplicationDirectoryListing*(self: FileSystem, path: string):
  Future[tuple[files: seq[string], folders: seq[string]]] {.base, gcsafe, raises: [].} = discard
method getApplicationFilePath*(self: FileSystem, name: string): string {.base, gcsafe, raises: [].} = discard
method loadApplicationFile*(self: FileSystem, name: string): string {.base, gcsafe, raises: [].} = discard
method loadApplicationFileAsync*(self: FileSystem, name: string): Future[string] {.base, gcsafe, raises: [].} = "".toFuture
method saveApplicationFile*(self: FileSystem, name: string, content: string) {.base, gcsafe, raises: [].} = discard

method findFile*(self: FileSystem, root: string, filenameRegex: string, maxResults: int = int.high): Future[seq[string]] {.base, gcsafe, async: (raises: []).} =
  return newSeq[string]()

method copyFile*(self: FileSystem, source: string, dest: string): Future[bool] {.base, gcsafe, async: (raises: []).} =
  return false

proc normalizePathUnix*(path: string): string {.gcsafe, raises: [].} =
  var stripLeading = false
  if path.startsWith("/") and path.len >= 3 and path[2] == ':':
    # Windows path: /C:/...
    stripLeading = true
  result = path.normalizedPath.replace('\\', '/').strip(leading=stripLeading, chars={'/'})
  if result.len >= 2 and result[1] == ':':
    result[0] = result[0].toUpperAscii

proc `//`*(a: string, b: string): string {.gcsafe, raises: [].} = (a / b).normalizePathUnix

when defined(js):
  import filesystem_browser
  let fs*: FileSystem = new FileSystemBrowser

else:
  import filesystem_desktop
  let fs*: FileSystem = new FileSystemDesktop
  fs.init getAppDir()
