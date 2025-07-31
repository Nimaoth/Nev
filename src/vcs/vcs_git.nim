import std/[strutils, strformat, options]
import misc/[async_process, custom_async, util, custom_logger]
import scripting_api, config_provider
import text/diff
import vfs
import vcs

{.push gcsafe.}
{.push raises: [].}

logCategory "vsc-git"

type
  VersionControlSystemGit* = ref object of VersionControlSystem
    settings: ConfigStore

proc newVersionControlSystemGit*(root: string, settings: ConfigStore): VersionControlSystemGit =
  new result
  result.root = root
  result.settings = settings

proc parseFileStatusGit(status: char): VCSFileStatus =
  result = case status
  of 'M': Modified
  of 'A': Added
  of 'D': Deleted
  of '?': Untracked
  else: None

proc parseGitRange(s: string): Result[(int, int), ref CatchableError] =
  if s.contains(','):
    let parts = s[1..^1].split(',')
    let first = ?catch(parts[0].parseInt - 1)
    let count = ?catch(parts[1].parseInt)
    if count == 0:
      return (first + 1, first + 1).ok
    # todo: -1 should maybe be done in a different place
    # return (first - 1, first - 1 + count)
    return (first, first + count).ok
  else:
    let first = ?catch(s[1..^1].parseInt - 1)
    # todo: -1 should maybe be done in a different place
    # return (first - 1, first + 1 - 1)
    return (first, first + 1).ok

method getChangedFiles*(self: VersionControlSystemGit): Future[seq[VCSFileInfo]] {.async.} =
  log lvlInfo, "getChangedFiles"

  let lines = runProcessAsync("git", @["status", "-s"], workingDir=self.root).await

  var files = newSeq[VCSFileInfo]()
  for line in lines:
    if line.len < 3:
      continue

    let stagedStatus = parseFileStatusGit(line[0])
    let unstagedStatus = parseFileStatusGit(line[1])

    let filePath = line[3..^1]

    files.add VCSFileInfo(
      stagedStatus: stagedStatus,
      unstagedStatus: unstagedStatus,
      path: self.root // filePath
    )

  return files

method stageFile*(self: VersionControlSystemGit, path: string): Future[string] {.async.} =
  let args = @["add", path]
  log lvlInfo, fmt"stage file: '{path}' -- {args}"
  return runProcessAsync("git", args, workingDir=self.root).await.join(" ")

method unstageFile*(self: VersionControlSystemGit, path: string): Future[string] {.async.} =
  let args = @["reset", path]
  log lvlInfo, fmt"unstage file: '{path}' -- {args}"
  return runProcessAsync("git", args, workingDir=self.root).await.join(" ")

method revertFile*(self: VersionControlSystemGit, path: string): Future[string] {.async.} =
  let args = @["checkout", path]
  log lvlInfo, fmt"revert file: '{path}' -- {args}"
  return runProcessAsync("git", args, workingDir=self.root).await.join(" ")

method getCommittedFileContent*(self: VersionControlSystemGit, path: string): Future[seq[string]] {.
    async.} =

  let args = @["show", "HEAD:" & path]
  log lvlInfo, fmt"getCommittedFileContent: '{path}' -- {args}"
  return runProcessAsync("git", args, workingDir=self.root).await

method getStagedFileContent*(self: VersionControlSystemGit, path: string): Future[seq[string]] {.async.} =
  let args = @["show", ":" & path]
  log lvlInfo, fmt"getStagedFileContent: '{path}' -- {args}"
  return runProcessAsync("git", args, workingDir=self.root).await

method getWorkingFileContent*(self: VersionControlSystemGit, path: string): Future[seq[string]] {.async.} =
  log lvlInfo, fmt"getWorkingFileContent '{path}'"
  var lines = newSeq[string]()
  for line in lines(path):
    lines.add line
  return lines

method getFileChanges*(self: VersionControlSystemGit, path: string, staged: bool = false):
    Future[Option[seq[LineMapping]]] {.async.} =

  var args = @["diff", "-U0", "--ignore-cr-at-eol"]

  let extraArgs = self.settings.get("vcs.git.diff-args", newSeq[string]())
  args.add extraArgs

  if staged:
    args.add "--staged"
  args.add path

  log lvlInfo, fmt"getFileChanges: '{path}' -- {args}"

  let lines = runProcessAsync("git", args, workingDir=self.root).await

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

    if deletedRaw.len == 0 or deletedRaw[0] != '-':
      log lvlError, &"Failed to handle removed line in git diff: '{line}'"
      return
    if addedRaw.len == 0 or addedRaw[0] != '+':
      log lvlError, &"Failed to handle added line in git diff: '{line}'"
      return

    let deletedRange = parseGitRange(deletedRaw).valueOr:
      log lvlError, &"Failed to parse deleted range: " & error.msg
      return seq[LineMapping].none
    let addedRange = parseGitRange(addedRaw).valueOr:
      log lvlError, &"Failed to parse deleted range: " & error.msg
      return seq[LineMapping].none

    # debug deletedRange, " -> ", addedRange
    current = LineMapping(
      source: deletedRange,
      target: addedRange,
    ).some

  if current.isSome:
    mappings.add current.get.move
    current = LineMapping.none

  return mappings.some
