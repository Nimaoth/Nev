import std/[dom, tables]
import misc/[custom_async, array_buffer]
import filesystem

type FileSystemBrowser* = ref object of FileSystem
  discard

proc jsLoadFileSync(path: cstring): cstring {.importc, nodecl.}
proc jsLoadFileAsync(path: cstring): Future[cstring] {.importc, nodecl.}
proc jsLoadFileBinaryAsync(path: cstring): Future[ArrayBuffer] {.importc, nodecl.}

method loadFile*(self: FileSystemBrowser, path: string): string =
  return $jsLoadFileSync(path.cstring)

method loadFileAsync*(self: FileSystemBrowser, name: string): Future[string] {.async.} =
  let res = await jsLoadFileAsync(name.cstring)
  return $res

method loadFileBinaryAsync*(self: FileSystemBrowser, name: string): Future[ArrayBuffer] =
  return jsLoadFileBinaryAsync(name.cstring)

method saveFile*(self: FileSystemBrowser, path: string, content: string) =
  discard

proc localStorageHasItem(name: cstring): bool {.importjs: "(window.localStorage.getItem(#) !== null)".}

var cachedAppFiles = initTable[string, string]()

method getApplicationFilePath*(self: FileSystemBrowser, name: string): string = ""

method loadApplicationFile*(self: FileSystemBrowser, name: string): string =
  if localStorageHasItem(name.cstring):
    return $window.localStorage.getItem(name.cstring)
  if not cachedAppFiles.contains(name):
    cachedAppFiles[name] = $jsLoadFileSync(name.cstring)
  return cachedAppFiles[name]

method saveApplicationFile*(self: FileSystemBrowser, name: string, content: string) =
  window.localStorage.setItem(name.cstring, content.cstring)