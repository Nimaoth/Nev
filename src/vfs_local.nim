import std/[os, options, unicode, strutils]
import misc/[custom_async, custom_logger, util, timer, regex]
import vfs

when defined(windows):
  import winim/lean

import nimsumtree/[rope]

{.push gcsafe.}
{.push raises: [].}

logCategory "vfs-local"

type
  VFSLocal* = ref object of VFS

proc loadFileThread(args: tuple[path: string, data: ptr string, flags: set[ReadFlag]]): bool =
  try:
    args.data[] = readFile(args.path)

    if ReadFlag.Binary notin args.flags:
      let invalidUtf8Index = args.data[].validateUtf8
      if invalidUtf8Index >= 0:
        args.data[] = &"Invalid utf-8 byte at {invalidUtf8Index}"
        return false

    return true

  except:
    args.data[] = getCurrentExceptionMsg()
    return false

method name*(self: VFSLocal): string = &"VFSLocal({self.prefix})"

method readImpl*(self: VFSLocal, path: string, flags: set[ReadFlag]): Future[string] {.async: (raises: [IOError]).} =
  if not path.isAbsolute:
    raise newException(IOError, &"Path not absolute '{path}'")
  if not fileExists(path):
    raise newException(FileNotFoundError, &"Not found '{path}'")

  try:
    logScope lvlInfo, &"[loadFile] '{path}'"
    var data = ""
    let ok = await spawnAsync(loadFileThread, (path, data.addr, flags))
    if not ok:
      raise newException(IOError, data)

    return data.move
  except:
    raise newException(IOError, getCurrentExceptionMsg(), getCurrentException())

method writeImpl*(self: VFSLocal, path: string, content: string): Future[void] {.async: (raises: [IOError]).} =
  if not path.isAbsolute:
    raise newException(IOError, &"Path not absolute '{path}'")

  try:
    logScope lvlInfo, &"[saveFile] '{path}'"
    # todo: reimplement async
    let dir = path.splitPath.head
    createDir(dir)
    writeFile(path, content)
    # var file = openAsync(path, fmWrite)
    # await file.write(content)
    # file.close()
  except:
    raise newException(IOError, getCurrentExceptionMsg(), getCurrentException())

method writeImpl*(self: VFSLocal, path: string, content: sink RopeSlice[int]): Future[void] {.async: (raises: [IOError]).} =
  if not path.isAbsolute:
    raise newException(IOError, &"Path not absolute '{path}'")

  try:
    logScope lvlInfo, &"[saveFile] '{path}'"
    # todo: reimplement async
    let dir = path.splitPath.head
    createDir(dir)
    writeFile(path, $content)
    # var file = openAsync(path, fmWrite)
    # for chunk in content.iterateChunks:
    #   await file.writeBuffer(chunk.chars[0].addr, chunk.chars.len)
    # file.close()
  except:
    raise newException(IOError, getCurrentExceptionMsg(), getCurrentException())

method getFileKindImpl*(self: VFSLocal, path: string): Future[Option[FileKind]] {.async: (raises: []).} =
  if fileExists(path):
    return FileKind.File.some
  if dirExists(path):
    return FileKind.Directory.some

  return FileKind.none

method getFileAttributesImpl*(self: VFSLocal, path: string): Future[Option[FileAttributes]] {.async: (raises: []).} =
  try:
    let permissions = path.getFilePermissions()
    log lvlInfo, &"[isFileReadOnly] Permissions for '{path}': {permissions}"
    return FileAttributes(writable: fpUserWrite in permissions, readable: fpUserRead in permissions).some
  except:
    return FileAttributes.none

method setFileAttributesImpl*(self: VFSLocal, path: string, attributes: FileAttributes): Future[void] {.async: (raises: [IOError]).} =
  try:
    var permissions = path.getFilePermissions()

    if attributes.writable:
      permissions.incl {fpUserWrite}
    else:
      permissions.excl {fpUserWrite}

    if attributes.readable:
      permissions.incl {fpUserRead}
    else:
      permissions.excl {fpUserRead}

    log lvlInfo, fmt"Try to change file permissions of '{path}' to {permissions}"
    path.setFilePermissions(permissions)

  except:
    raise newException(IOError, fmt"Failed to change file permissions of '{path}': " & getCurrentExceptionMsg(), getCurrentException())

method normalizeImpl*(self: VFSLocal, path: string): string =
  try:
    return path.absolutePath
  except:
    return path

proc fillDirectoryListing(directoryListing: var DirectoryListing, path: string, relative: bool = true) =
  try:
    for (kind, name) in walkDir(path, relative=relative):
      case kind
      of pcFile:
        directoryListing.files.add name
      of pcDir:
        directoryListing.folders.add name
      else:
        log lvlError, fmt"getDirectoryListing: Unhandled file type {kind} for {name}"

  except OSError:
    discard

method getDirectoryListingImpl*(self: VFSLocal, path: string): Future[DirectoryListing] {.async: (raises: []).} =
  if path.len == 0:
    when defined(windows):
      var chars: array[1024, char]
      let len = GetLogicalDriveStringsA(chars.len.DWORD, cast[LPSTR](chars[0].addr)).int
      if len == 0:
        result.folders.add "C:"
      else:
        var index = 0
        while true:
          let nextIndex = chars.toOpenArray(0, chars.high).find('\0', index)
          if nextIndex == index or nextIndex == -1 or index >= chars.len:
            break

          let colonIndex = chars.find(':', index)
          if colonIndex != -1:
            result.folders.add chars[index..colonIndex].join("")

          index = nextIndex + 1

    else:
      result.fillDirectoryListing("/", relative = false)

  else:
    when defined(posix):
      if path == "/":
        result.fillDirectoryListing("/", relative = false)
        return

    result.fillDirectoryListing(path)

method copyFileImpl*(self: VFSLocal, src: string, dest: string): Future[void] {.async: (raises: [IOError]).} =
  try:
    let dir = dest.splitPath.head
    createDir(dir)
    copyFileWithPermissions(src, dest)
  except Exception as e:
    raise newException(IOError, &"Failed to copy file '{src}' to '{dest}': {e.msg}", e)

proc findFilesRec(dir: string, relDir: string, filename: Regex, maxResults: int, res: var seq[string]) =
  try:
    for (kind, name) in walkDir(dir, relative=true):
      case kind
      of pcFile:
        if name.contains(filename):
          res.add relDir // name
          if res.len >= maxResults:
            return

      of pcDir:
        findFilesRec(dir // name, relDir // name, filename, maxResults, res)
        if res.len >= maxResults:
          return
      else:
        discard

  except:
    discard

proc findFileThread(args: tuple[root: string, filename: string, maxResults: int, res: ptr seq[string]]) =
  try:
    let filenameRegex = re(args.filename)
    findFilesRec(args.root, "", filenameRegex, args.maxResults, args.res[])
  except RegexError:
    discard

method findFilesImpl*(self: VFSLocal, root: string, filenameRegex: string, maxResults: int = int.high): Future[seq[string]] {.async: (raises: []).} =
  var res = newSeq[string]()
  try:
    await spawnAsync(findFileThread, (root, filenameRegex, maxResults, res.addr))
  except Exception as e:
    log lvlError, &"Failed to find files in {self.name}/{root}"
  return res
