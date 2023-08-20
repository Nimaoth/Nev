import std/[os]
import filesystem, custom_logger

logCategory "fs-desktop"

type FileSystemDesktop* = ref object of FileSystem
  discard

method loadFile*(self: FileSystemDesktop, path: string): string =
  return readFile(path)

method saveFile*(self: FileSystemDesktop, path: string, content: string) =
  writeFile(path, content)

method getApplicationFilePath*(self: FileSystemDesktop, name: string): string =
  when defined(js):
    return name
  else:
    return getAppDir() / name

method loadApplicationFile*(self: FileSystemDesktop, name: string): string =
  let path = self.getApplicationFilePath name
  debugf"loadApplicationFile {name} -> {path}"
  return readFile(path)

method saveApplicationFile*(self: FileSystemDesktop, name: string, content: string) =
  let path = self.getApplicationFilePath name
  debugf"saveApplicationFile {name} -> {path}"
  writeFile(path, content)