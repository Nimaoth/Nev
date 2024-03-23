import std/[os]
import misc/[custom_logger]
import filesystem

logCategory "fs-desktop"

type FileSystemDesktop* = ref object of FileSystem
  appDir*: string

method init*(self: FileSystemDesktop, appDir: string) =
  self.appDir = appDir

method loadFile*(self: FileSystemDesktop, path: string): string =
  return readFile(path)

method saveFile*(self: FileSystemDesktop, path: string, content: string) =
  writeFile(path, content)

method getApplicationFilePath*(self: FileSystemDesktop, name: string): string =
  when defined(js):
    return name
  else:
    if isAbsolute(name):
      return name
    else:
      return self.appDir / name

method loadApplicationFile*(self: FileSystemDesktop, name: string): string =
  let path = self.getApplicationFilePath name
  log lvlInfo, fmt"loadApplicationFile {name} -> {path}"
  try:
    return readFile(path)
  except:
    log lvlError, fmt"Failed to load application file {path}: {getCurrentExceptionMsg()}"
    return ""

method saveApplicationFile*(self: FileSystemDesktop, name: string, content: string) =
  let path = self.getApplicationFilePath name
  log lvlInfo, fmt"saveApplicationFile {name} -> {path}"
  try:
    writeFile(path, content)
  except:
    log lvlError, fmt"Failed to save application file {path}: {getCurrentExceptionMsg()}"
