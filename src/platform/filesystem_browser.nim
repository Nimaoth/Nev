import filesystem

type FileSystemBrowser* = ref object of FileSystem
  discard

proc loadFileSync(path: cstring): cstring {.importc, nodecl.}

method loadFile*(self: FileSystemBrowser, path: string): string =
  return $loadFileSync(path.cstring)

method saveFile*(self: FileSystemBrowser, path: string, content: string) =
  discard

method loadApplicationFile*(self: FileSystemBrowser, name: string): string =
  return $loadFileSync(name.cstring)

method saveApplicationFile*(self: FileSystemBrowser, name: string, content: string) =
  discard