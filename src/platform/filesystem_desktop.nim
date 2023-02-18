import filesystem

type FileSystemDesktop* = ref object of FileSystem
  discard

method loadFile*(self: FileSystemDesktop, path: string): string =
  return readFile(path)

method saveFile*(self: FileSystemDesktop, path: string, content: string) =
  writeFile(path, content)

method loadApplicationFile*(self: FileSystemDesktop, name: string): string =
  return readFile(name)

method saveApplicationFile*(self: FileSystemDesktop, name: string, content: string) =
  writeFile(name, content)