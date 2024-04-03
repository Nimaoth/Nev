import std/[strutils, sequtils, strformat, os, tables, options, enumutils]
import misc/[async_process, custom_async, util, custom_logger]
import scripting_api

logCategory "diff-git"

type
  FileStatus* = enum None = " ", Modified = "M", Added = "A", Deleted = "D", Untracked = "?"
  GitFileInfo* = object
    stagedStatus*: FileStatus
    unstagedStatus*: FileStatus
    path*: string

  LineMapping* = object
    source*: tuple[first: int, last: int]
    target*: tuple[first: int, last: int]
    lines*: seq[string]

proc parseFileStatusGit(status: char): FileStatus =
  result = case status
  of 'M': Modified
  of 'A': Added
  of 'D': Deleted
  of '?': Untracked
  else: None

proc getCommitedFileContent*(path: string): Future[seq[string]] {.async.} =
  let args = @["show", "HEAD:" & path]
  log lvlInfo, fmt"getCommitedFileContent: '{path}' -- {args}"
  return runProcessAsync("git", args).await

proc getStagedFileContent*(path: string): Future[seq[string]] {.async.} =
  let args = @["show", ":" & path]
  log lvlInfo, fmt"getStagedFileContent: '{path}' -- {args}"
  return runProcessAsync("git", args).await

proc getWorkingFileContent(path: string): Future[seq[string]] {.async.} =
  log lvlInfo, fmt"getWorkingFileContent '{path}'"
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

  for map in changes:
    # add unchanged lines before change
    for i in currentLineSource..map.source.first:
      # debug "take ", i + 1, ": ", lines[i]
      result.add lines[i]

    currentLineSource = map.source.last + 1

    for line in map.lines:
      # debug "insert ", line
      result.add line

  # add unchanged lines after last change
  for i in currentLineSource..lines.high:
    # debug "take ", i + 1, ": ", lines[i]
    result.add lines[i]

proc getFileChanges*(path: string, staged: bool = false): Future[Option[seq[LineMapping]]] {.async.} =
  var args = @["diff", "-U0"]
  if staged:
    args.add "--staged"
  args.add path

  log lvlInfo, fmt"getFileChanges: '{path}' -- {args}"

  let lines = runProcessAsync("git", args).await

  var mappings = newSeq[LineMapping]()

  var current = LineMapping.none

  for line in lines:
    if line.startsWith("Binary files"):
      # binary file, no line diffs
      return seq[LineMapping].none

    if line.startsWith("+"):
      if current.isNone:
        continue

      current.get.lines.add line[1..^1]
      continue

    if not line.startsWith("@@"):
      continue

    if current.isSome:
      mappings.add current.get.move
      current = LineMapping.none

    let parts = line.split " "

    if parts.len < 4:
      continue

    let deletedRaw = parts[1]
    let addedRaw = parts[2]
    # debug deletedRaw, " -> ", addedRaw

    assert deletedRaw[0] == '-'
    assert addedRaw[0] == '+'

    let deletedRange = parseGitRange(deletedRaw)
    let addedRange = parseGitRange(addedRaw)

    # debug deletedRange, " -> ", addedRange
    current = LineMapping(
      source: deletedRange,
      target: addedRange,
    ).some

  if current.isSome:
    mappings.add current.get.move
    current = LineMapping.none

  return mappings.some

proc getChangedFiles*(): Future[seq[GitFileInfo]] {.async.} =
  log lvlInfo, "getChangedFiles"

  let lines = runProcessAsync("git", @["status", "-s"]).await

  var files = newSeq[GitFileInfo]()
  for line in lines:
    if line.len < 3:
      continue

    let stagedStatus = parseFileStatusGit(line[0])
    let unstagedStatus = parseFileStatusGit(line[1])

    let filePath = line[3..^1]

    files.add GitFileInfo(
      stagedStatus: stagedStatus,
      unstagedStatus: unstagedStatus,
      path: filePath
    )

  return files


when isMainModule:
  logger.enableConsoleLogger()
  proc test() {.async.} =
    let files = getChangedFiles().await
    debug files.mapIt($it).join("\n")

    for i, file in files:
      if i > 100:
        break

      debug "---------------------------------------------------------------------------------------------------------------------------------------------------------"
      let mappings = await getFileChanges(file.path, staged=false)
      let mappings2 = await getFileChanges(file.path, staged=true)

      if mappings.isNone or mappings2.isNone:
        # probably binary file
        debugf"Binary file {file.path}"
        continue

      let committed = getCommitedFileContent(file.path).await
      let staged = getStagedFileContent(file.path).await
      let working = getWorkingFileContent(file.path).await

      let test1 = staged.applyChanges(mappings.get, working)
      let test2 = committed.applyChanges(mappings2.get, staged)

      # debug committed
      # debug staged
      # debug working

      debug fmt"commited: {committed.len}, staged: {staged.len}, working: {working.len}, test1: {test1.len}, test2: {test2.len}"

      for i in 0..min(test1.high, working.high):
        if test1[i] != working[i]:
          debug "different: ", i
      debug test1 == working

      for i in 0..min(test2.high, staged.high):
        if test2[i] != staged[i]:
          debug "different: ", i
      debug test2 == staged

  asyncCheck test()

  while hasPendingOperations():
    poll(1000)
