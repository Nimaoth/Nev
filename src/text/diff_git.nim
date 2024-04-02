import std/[strutils, sequtils, strformat, os, tables, options, enumutils]
import misc/[async_process, custom_async, util]
import scripting_api

type
  FileStatus = enum None, Modified, Added, Deleted, Untracked
  FileInfo = object
    stagedStatus: FileStatus
    unstagedStatus: FileStatus
    path: string

  LineMapping = object
    source: tuple[first: int, last: int]
    target: tuple[first: int, last: int]
    lines: seq[string]

proc parseFileStatusGit(status: char): FileStatus =
  result = case status
  of 'M': Modified
  of 'A': Added
  of 'D': Deleted
  of '?': Untracked
  else: None

proc getCommitedFileContent(path: string): Future[seq[string]] {.async.} =
  let args = @["show", "HEAD:" & path]
  echo fmt"getCommitedFileContent: '{path}' -- {args}"
  let p = startAsyncProcess("git", args, autoRestart = false, autoStart = false)
  discard p.start()

  var lines = newSeq[string]()
  while true:
    let line = p.tryRecvLine().await
    if line.isNone:
      break
    lines.add line.get

  p.destroy()

  return lines

proc getStagedFileContent(path: string): Future[seq[string]] {.async.} =
  let args = @["show", ":" & path]
  echo fmt"getStagedFileContent: '{path}' -- {args}"
  let p = startAsyncProcess("git", args, autoRestart = false, autoStart = false)
  discard p.start()

  var lines = newSeq[string]()
  while true:
    let line = p.tryRecvLine().await
    if line.isNone:
      break
    lines.add line.get

  p.destroy()

  return lines

proc getWorkingFileContent(path: string): Future[seq[string]] {.async.} =
  echo fmt"getWorkingFileContent '{path}'"
  var lines = newSeq[string]()
  for line in lines(path):
    lines.add line
  return lines

proc parseGitRange(s: string): (int, int) =
  if s.contains(','):
    let parts = s[1..^1].split(',')
    let first = parts[0].parseInt - 1
    let count = parts[1].parseInt
    if count == 0:
      return (first, first)
    # todo: -1 should maybe be done in a different place
    return (first - 1, first - 1 + count)
  else:
    let first = s[1..^1].parseInt - 1
    # todo: -1 should maybe be done in a different place
    return (first - 1, first + 1 - 1)

proc applyChanges(lines: openArray[string], changes: openArray[LineMapping], expected: openArray[string]): seq[string] =
  var currentLineSource = 0
  var currentLineTarget = 0

  for map in changes:
    # add unchanged lines before change
    for i in currentLineSource..map.source.first:
      # echo "take ", i + 1, ": ", lines[i]
      result.add lines[i]

    currentLineSource = map.source.last + 1

    for line in map.lines:
      # echo "insert ", line
      result.add line

  # add unchanged lines after last change
  for i in currentLineSource..lines.high:
    # echo "take ", i + 1, ": ", lines[i]
    result.add lines[i]

proc getFileChanges(path: string, staged: bool = false): Future[seq[LineMapping]] {.async.} =
  var args = @["diff", "-U0"]
  if staged:
    args.add "--staged"
  args.add path

  echo fmt"getFileChanges: '{path}' -- {args}"
  let p = startAsyncProcess("git", args, autoRestart = false, autoStart = false)
  discard p.start()

  var mappings = newSeq[LineMapping]()

  var current = LineMapping.none

  while true:
    let line = p.tryRecvLine().await
    if line.isNone:
      break

    let lineRaw = line.get

    if lineRaw.startsWith("+"):
      if current.isNone:
        continue

      current.get.lines.add lineRaw[1..^1]
      continue

    if not lineRaw.startsWith("@@"):
      continue

    if current.isSome:
      mappings.add current.get.move
      current = LineMapping.none

    let parts = lineRaw.split " "

    if parts.len < 4:
      continue

    let deletedRaw = parts[1]
    let addedRaw = parts[2]
    echo deletedRaw, " -> ", addedRaw

    assert deletedRaw[0] == '-'
    assert addedRaw[0] == '+'

    let deletedRange = parseGitRange(deletedRaw)
    let addedRange = parseGitRange(addedRaw)

    echo deletedRange, " -> ", addedRange
    current = LineMapping(
      source: deletedRange,
      target: addedRange,
    ).some

  if current.isSome:
    mappings.add current.get.move
    current = LineMapping.none

  p.destroy()

  echo mappings.mapIt($it).join("\n")
  return mappings

proc getChangedFiles(): Future[seq[FileInfo]] {.async.} =
  echo "getChangedFiles"
  let p = startAsyncProcess("git", @["status", "-s"], autoRestart = false, autoStart = false)
  discard p.start()

  var lines = newSeq[FileInfo]()
  while true:
    let line = p.tryRecvLine().await
    if line.isNone:
      break

    if line.get.len < 3:
      continue

    let fileInfoRaw = line.get
    let status = fileInfoRaw[0..1]

    let stagedStatus = parseFileStatusGit(fileInfoRaw[0])
    let unstagedStatus = parseFileStatusGit(fileInfoRaw[1])

    let filePath = fileInfoRaw[3..^1]

    lines.add FileInfo(
      stagedStatus: stagedStatus,
      unstagedStatus: unstagedStatus,
      path: filePath
    )

  p.destroy()

  echo lines.mapIt($it).join("\n")

  for file in lines:
    echo "---------------------------------------------------------------------------------------------------------------------------------------------------------"
    let mappings = await getFileChanges(file.path, staged=false)
    let mappings2 = await getFileChanges(file.path, staged=true)

    let committed = getCommitedFileContent(file.path).await
    let staged = getStagedFileContent(file.path).await
    let working = getWorkingFileContent(file.path).await

    let test1 = staged.applyChanges(mappings, working)
    let test2 = committed.applyChanges(mappings2, staged)

    echo fmt"commited: {committed.len}, staged: {staged.len}, working: {working.len}, test1: {test1.len}, test2: {test2.len}"

    for i in 0..min(test1.high, working.high):
      if test1[i] != working[i]:
        echo "different: ", i
    echo test1 == working

    for i in 0..min(test2.high, staged.high):
      if test2[i] != staged[i]:
        echo "different: ", i
    echo test2 == staged

  return lines

asyncCheck getChangedFiles()

while hasPendingOperations():
  poll(1000)
