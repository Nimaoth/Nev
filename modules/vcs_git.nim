import std/[strutils, strformat, options]
import misc/[async_process, custom_async, util, custom_logger]
import vfs
import vcs/vcs

const currentSourcePath2 = currentSourcePath()
include module_base

{.push gcsafe.}
{.push raises: [].}

when implModule:
  import std/[tables]
  import text/diff
  import service, config_provider
  import misc/[delayed_task]

  logCategory "vsc-git"

  type
    VersionControlSystemGit* = ref object of VersionControlSystem
      settings: ConfigStore
      updateStatusTask: DelayedTask

  proc gitUpdateStatus(self: VersionControlSystemGit): Future[void] {.gcsafe, async: (raises: []).} =
    try:
      var args = @["status", "-b", "--porcelain=2"]

      const branchHead = "# branch.head "
      const branchUpstream = "# branch.upstream "
      const branchAb = "# branch.ab "

      var branch = "main"
      var upstream = "origin/main"
      var ap = (ahead: 0, behind: 0)

      let lines = runProcessAsync("git", args, workingDir=self.root, log = false).await
      for line in lines:
        if line.startsWith(branchHead):
          branch = line[branchHead.len..^1]
        elif line.startsWith(branchUpstream):
          upstream = line[branchUpstream.len..^1]
        elif line.startsWith(branchAb):
          let parts = line[branchAb.len..^1].split(" ")
          if parts.len == 2:
            ap.ahead = parts[0].parseInt.catch(0)
            ap.behind = parts[1].parseInt.catch(0)

      self.status = &"{branch} {ap.ahead}↑ {ap.behind}↓"
    except CatchableError as e:
      log lvlWarn, &"Failed to update git status: {e.msg}"

  proc parseFileStatusGit(status: char): VCSFileStatus =
    result = case status
    of 'M': Modified
    of 'A': Added
    of 'D': Deleted
    of 'U': Conflict
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

  proc gitGetChangedFiles(self: VersionControlSystemGit): Future[seq[VCSChangelist]] {.gcsafe, async: (raises: []).} =
    log lvlInfo, "getChangedFiles"

    try:
      let lines = runProcessAsync("git", @["status", "-s"], workingDir=self.root).await

      var stagedFiles = newSeq[VCSFileInfo]()
      var workingFiles = newSeq[VCSFileInfo]()

      for line in lines:
        if line.len < 3:
          continue

        let stagedStatus = parseFileStatusGit(line[0])
        let unstagedStatus = parseFileStatusGit(line[1])

        let filePath = line[3..^1]
        let fullPath = self.root // filePath

        # Add to staged changelist if file has staged changes
        if stagedStatus != None and stagedStatus != Untracked:
          stagedFiles.add VCSFileInfo(
            stagedStatus: stagedStatus,
            unstagedStatus: None,
            path: fullPath
          )

        # Add to working changelist if file has unstaged changes
        if unstagedStatus != None:
          workingFiles.add VCSFileInfo(
            stagedStatus: None,
            unstagedStatus: unstagedStatus,
            path: fullPath
          )

      var changelists = newSeq[VCSChangelist]()

      # Add staged changelist first if it has files
      if stagedFiles.len > 0:
        changelists.add VCSChangelist(
          id: "staged",
          description: "Staged changes",
          author: "",
          files: stagedFiles
        )

      # Add working changelist if it has files
      if workingFiles.len > 0:
        changelists.add VCSChangelist(
          id: "working",
          description: "Working changes",
          author: "",
          files: workingFiles
        )

      return changelists
    except CatchableError as e:
      return @[]

  proc gitGetCommitHistory(self: VersionControlSystemGit, maxCount: int = 50): Future[seq[VCSCommitInfo]] {.gcsafe, async: (raises: []).} =
    try:
      let args = @["log", &"--max-count={maxCount}", "--format=%h%n%s%n%ai%n%an"]
      let output = runProcessAsync("git", args, workingDir=self.root, log = false).await

      var commits = newSeq[VCSCommitInfo]()
      var i = 0
      while i + 3 < output.len:
        commits.add VCSCommitInfo(
          id: output[i],
          description: output[i + 1],
          date: output[i + 2],
          author: output[i + 3],
        )
        i += 4

      return commits
    except CatchableError as e:
      return @[]

  proc gitStageFile(self: VersionControlSystemGit, path: string): Future[string] {.gcsafe, async: (raises: []).} =
    try:
      let args = @["add", path]
      log lvlInfo, fmt"stage file: '{path}' -- {args}"
      return runProcessAsync("git", args, workingDir=self.root).await.join(" ")
    except CatchableError:
      return ""

  proc gitUnstageFile(self: VersionControlSystemGit, path: string): Future[string] {.gcsafe, async: (raises: []).} =
    try:
      let args = @["reset", path]
      log lvlInfo, fmt"unstage file: '{path}' -- {args}"
      return runProcessAsync("git", args, workingDir=self.root).await.join(" ")
    except CatchableError:
      return ""

  proc gitRevertFile(self: VersionControlSystemGit, path: string): Future[string] {.gcsafe, async: (raises: []).} =
    try:
      let args = @["checkout", path]
      log lvlInfo, fmt"revert file: '{path}' -- {args}"
      return runProcessAsync("git", args, workingDir=self.root).await.join(" ")
    except CatchableError:
      return ""

  proc gitGetCommittedFileContent(self: VersionControlSystemGit, path: string): Future[seq[string]] {.gcsafe, async: (raises: []).} =
    try:
      let args = @["show", "HEAD:" & path]
      log lvlInfo, fmt"getCommittedFileContent: '{path}' -- {args}"
      return runProcessAsync("git", args, workingDir=self.root).await
    except CatchableError:
      return @[]

  proc gitGetStagedFileContent(self: VersionControlSystemGit, path: string): Future[seq[string]] {.gcsafe, async: (raises: []).} =
    try:
      let args = @["show", ":" & path]
      log lvlInfo, fmt"getStagedFileContent: '{path}' -- {args}"
      return runProcessAsync("git", args, workingDir=self.root).await
    except CatchableError:
      return @[]

  proc gitGetWorkingFileContent(self: VersionControlSystemGit, path: string): Future[seq[string]] {.gcsafe, async: (raises: []).} =
    try:
      log lvlInfo, fmt"getWorkingFileContent '{path}'"
      var lines = newSeq[string]()
      for line in lines(path):
        lines.add line
      return lines
    except CatchableError:
      return @[]

  proc gitGetFileChanges(self: VersionControlSystemGit, path: string, staged: bool = false):
      Future[Option[seq[LineMapping]]] {.gcsafe, async: (raises: []).} =
    try:
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
    except CatchableError:
      return seq[LineMapping].none

  proc newVersionControlSystemGit*(root: string, settings: ConfigStore): VersionControlSystemGit =
    new result
    result.name = "Git"
    result.root = root
    result.settings = settings
    result.updateStatusImpl = proc(self: VersionControlSystem) {.gcsafe, raises: [].} =
      asyncSpawn self.VersionControlSystemGit.gitUpdateStatus()
    result.getChangedFilesImpl = proc(self: VersionControlSystem): Future[seq[VCSChangelist]] {.gcsafe, async: (raises: []).} =
      return await self.VersionControlSystemGit.gitGetChangedFiles()
    result.getCommitHistoryImpl = proc(self: VersionControlSystem, maxCount: int = 50): Future[seq[VCSCommitInfo]] {.gcsafe, async: (raises: []).} =
      return await self.VersionControlSystemGit.gitGetCommitHistory(maxCount)
    result.stageFileImpl = proc(self: VersionControlSystem, path: string): Future[string] {.gcsafe, async: (raises: []).} =
      return await self.VersionControlSystemGit.gitStageFile(path)
    result.unstageFileImpl = proc(self: VersionControlSystem, path: string): Future[string] {.gcsafe, async: (raises: []).} =
      return await self.VersionControlSystemGit.gitUnstageFile(path)
    result.revertFileImpl = proc(self: VersionControlSystem, path: string): Future[string] {.gcsafe, async: (raises: []).} =
      return await self.VersionControlSystemGit.gitRevertFile(path)
    result.getCommittedFileContentImpl = proc(self: VersionControlSystem, path: string): Future[seq[string]] {.gcsafe, async: (raises: []).} =
      return await self.VersionControlSystemGit.gitGetCommittedFileContent(path)
    result.getStagedFileContentImpl = proc(self: VersionControlSystem, path: string): Future[seq[string]] {.gcsafe, async: (raises: []).} =
      return await self.VersionControlSystemGit.gitGetStagedFileContent(path)
    result.getWorkingFileContentImpl = proc(self: VersionControlSystem, path: string): Future[seq[string]] {.gcsafe, async: (raises: []).} =
      return await self.VersionControlSystemGit.gitGetWorkingFileContent(path)
    result.getFileChangesImpl = proc(self: VersionControlSystem, path: string, staged: bool = false): Future[Option[seq[LineMapping]]] {.gcsafe, async: (raises: []).} =
      return await self.VersionControlSystemGit.gitGetFileChanges(path, staged)

    let self = result
    asyncSpawn self.gitUpdateStatus()
    self.updateStatusTask = startDelayed(self.settings.get("git.update-status-interval", 5000), true):
      self.updateStatusTask.interval = self.settings.get("git.update-status-interval", 5000).int64
      asyncSpawn self.gitUpdateStatus()

  iterator walkGitDirs(dir: string): string {.raises: [OSError].} =
    var stack = @[""]
    while stack.len > 0:
      let d = stack.pop()
      for k, p in walkDir(dir / d, relative = true, checkDir = false, skipSpecial = true):
        let rel = d / p
        if k in {pcDir, pcLinkToDir} and k in {pcDir}:
          stack.add rel
        if k in {pcDir}:
          if p == ".git":
            yield dir // d

  proc detectGit(path: string): seq[VersionControlSystem] =
    let config = getServiceChecked(ConfigService).runtime

    if dirExists(path // ".git"):
      log lvlInfo, fmt"Found git repository in {path}"
      let vcs = newVersionControlSystemGit(path, config)
      return @[vcs.VersionControlSystem]

    try:
      for path in walkGitDirs(path):
        log lvlInfo, fmt"Found git repository in {path}"
        let vcs = newVersionControlSystemGit(path, config)
        result.add vcs.VersionControlSystem
    except OSError:
      discard

  proc init_module_vcs_git*() {.cdecl, exportc, dynlib.} =
    let services = getServices()
    if services == nil:
      log lvlWarn, &"Failed to initialize init_module_vcs_git: no services found"
      return

    let vcs = services.getService(VCSService).get
    vcs.detectors["git"] = detectGit
