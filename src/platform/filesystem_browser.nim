import filesystem

type FileSystemBrowser* = ref object of FileSystem
  discard

method loadFile*(self: FileSystemBrowser, path: string): string =
  discard

method saveFile*(self: FileSystemBrowser, path: string, content: string) =
  discard

method loadApplicationFile*(self: FileSystemBrowser, name: string): string =
  discard

method saveApplicationFile*(self: FileSystemBrowser, name: string, content: string) =
  discard