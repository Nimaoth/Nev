type FileSystem* = ref object of RootObj
  discard

method loadFile*(self: FileSystem, path: string): string {.base.} = discard
method saveFile*(self: FileSystem, path: string, content: string) {.base.} = discard

method loadApplicationFile*(self: FileSystem, name: string): string {.base.} = discard
method saveApplicationFile*(self: FileSystem, name: string, content: string) {.base.} = discard

when defined(js):
  import filesystem_browser
  let fs*: FileSystem = new FileSystemBrowser

else:
  import filesystem_desktop
  let fs*: FileSystem = new FileSystemDesktop
