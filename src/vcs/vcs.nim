import std/[options, tables]
import misc/[custom_async, custom_logger, util]
import text/diff
import nimsumtree/[arc]
import workspaces/workspace
import service, config_provider, vfs, vfs_service

include dynlib_export

{.push gcsafe.}
{.push raises: [].}

logCategory "vcs"

type
  VCSFileStatus* = enum None = ".", Modified = "M", Added = "A", Deleted = "D", Conflict = "U", Untracked = "?"
  VCSFileInfo* = object
    stagedStatus*: VCSFileStatus
    unstagedStatus*: VCSFileStatus
    path*: string

  VCSChangelist* = object
    id*: string
    description*: string
    author*: string
    files*: seq[VCSFileInfo]

  VCSCommitInfo* = object
    id*: string
    description*: string
    date*: string
    author*: string

  VCSStashInfo* = object
    id*: string
    description*: string
    date*: string
    author*: string

  VersionControlSystem* = ref object of RootObj
    name*: string
    root*: string
    status*: string
    updateStatusImpl*: proc(self: VersionControlSystem) {.gcsafe, raises: [].}
    stageFileImpl*: proc(self: VersionControlSystem, path: string): Future[string] {.gcsafe, async: (raises: []).}
    unstageFileImpl*: proc(self: VersionControlSystem, path: string): Future[string] {.gcsafe, async: (raises: []).}
    revertFileImpl*: proc(self: VersionControlSystem, path: string): Future[string] {.gcsafe, async: (raises: []).}
    getCommittedFileContentImpl*: proc(self: VersionControlSystem, path: string, commit: string = ""): Future[seq[string]] {.gcsafe, async: (raises: []).}
    getStagedFileContentImpl*: proc(self: VersionControlSystem, path: string): Future[seq[string]] {.gcsafe, async: (raises: []).}
    getWorkingFileContentImpl*: proc(self: VersionControlSystem, path: string): Future[seq[string]] {.gcsafe, async: (raises: []).}
    getFileChangesImpl*: proc(self: VersionControlSystem, path: string, staged: bool = false): Future[Option[seq[LineMapping]]] {.gcsafe, async: (raises: []).}
    checkoutFileImpl*: proc(self: VersionControlSystem, path: string): Future[string] {.gcsafe, async: (raises: []).}
    addFileImpl*: proc(self: VersionControlSystem, path: string): Future[string] {.gcsafe, async: (raises: []).}
    getChangedFilesImpl*: proc(self: VersionControlSystem): Future[seq[VCSChangelist]] {.gcsafe, async: (raises: []).}
    getCommitHistoryImpl*: proc(self: VersionControlSystem, maxCount: int = 50): Future[seq[VCSCommitInfo]] {.gcsafe, async: (raises: []).}
    getStashesImpl*: proc(self: VersionControlSystem, maxCount: int = 50, filter: string = ""): Future[seq[VCSStashInfo]] {.gcsafe, async: (raises: []).}

type
  VCSDetector* = proc(rootDir: string): seq[VersionControlSystem] {.gcsafe, raises: [].}

  VCSService* = ref object of Service
    config*: ConfigService
    workspace*: Workspace
    versionControlSystems*: seq[VersionControlSystem]
    vfs*: VFS
    vfs2*: Arc[VFS2]
    detectors*: Table[string, VCSDetector]

func serviceName*(_: typedesc[VCSService]): string = "VCSService"

{.push apprtl, gcsafe, raises: [].}
proc vcsGetVcsForFile(self: VCSService, file: string): Option[VersionControlSystem]
{.pop.}

proc getVcsForFile*(self: VCSService, file: string): Option[VersionControlSystem] = vcsGetVcsForFile(self, file)

proc updateStatus*(self: VersionControlSystem) =
  if self.updateStatusImpl != nil:
    self.updateStatusImpl(self)

proc stageFile*(self: VersionControlSystem, path: string): Future[string] {.gcsafe, async: (raises: []).} =
  if self.stageFileImpl != nil:
    return await self.stageFileImpl(self, path)

proc unstageFile*(self: VersionControlSystem, path: string): Future[string] {.gcsafe, async: (raises: []).} =
  if self.unstageFileImpl != nil:
    return await self.unstageFileImpl(self, path)

proc revertFile*(self: VersionControlSystem, path: string): Future[string] {.gcsafe, async: (raises: []).} =
  if self.revertFileImpl != nil:
    return await self.revertFileImpl(self, path)

proc getCommittedFileContent*(self: VersionControlSystem, path: string, commit: string = ""): Future[seq[string]] {.gcsafe, async: (raises: []).} =
  if self.getCommittedFileContentImpl != nil:
    return await self.getCommittedFileContentImpl(self, path, commit)

proc getStagedFileContent*(self: VersionControlSystem, path: string): Future[seq[string]] {.gcsafe, async: (raises: []).} =
  if self.getStagedFileContentImpl != nil:
    return await self.getStagedFileContentImpl(self, path)

proc getWorkingFileContent*(self: VersionControlSystem, path: string): Future[seq[string]] {.gcsafe, async: (raises: []).} =
  if self.getWorkingFileContentImpl != nil:
    return await self.getWorkingFileContentImpl(self, path)

proc getFileChanges*(self: VersionControlSystem, path: string, staged: bool = false): Future[Option[seq[LineMapping]]] {.gcsafe, async: (raises: []).} =
  if self.getFileChangesImpl != nil:
    return await self.getFileChangesImpl(self, path, staged)

proc checkoutFile*(self: VersionControlSystem, path: string): Future[string] {.gcsafe, async: (raises: []).} =
  if self.checkoutFileImpl != nil:
    return await self.checkoutFileImpl(self, path)

proc addFile*(self: VersionControlSystem, path: string): Future[string] {.gcsafe, async: (raises: []).} =
  if self.addFileImpl != nil:
    return await self.addFileImpl(self, path)

proc getChangedFiles*(self: VersionControlSystem): Future[seq[VCSChangelist]] {.gcsafe, async: (raises: []).} =
  if self.getChangedFilesImpl != nil:
    return await self.getChangedFilesImpl(self)

proc getCommitHistory*(self: VersionControlSystem, maxCount: int = 50): Future[seq[VCSCommitInfo]] {.gcsafe, async: (raises: []).} =
  if self.getCommitHistoryImpl != nil:
    return await self.getCommitHistoryImpl(self, maxCount)

proc getStashes*(self: VersionControlSystem, maxCount: int = 50, filter: string = ""): Future[seq[VCSStashInfo]] {.gcsafe, async: (raises: []).} =
  if self.getStashesImpl != nil:
    return await self.getStashesImpl(self, maxCount, filter)

when implModule:
  import std/[strutils, sugar]
  import misc/[event]
  addBuiltinService(VCSService, Workspace, ConfigService, VFSService)

  func isUntracked*(fileInfo: VCSFileInfo): bool = fileInfo.unstagedStatus == Untracked

  proc handleWorkspaceFolderAdded(self: VCSService, path: string) {.async: (raises: []).} =
    try:
      for detector in self.detectors.values:
        for vcs in detector(path):
          self.versionControlSystems.add vcs

    except CatchableError as e:
      log lvlError, &"Failed to detect version control systems: {e.msg}\n{e.getStackTrace()}"

  method init*(self: VCSService): Future[Result[void, ref CatchableError]] {.async: (raises: []).} =
    log lvlInfo, &"VCSService.init"
    self.config = self.services.getService(ConfigService).get
    self.vfs = self.services.getService(VFSService).get.vfs
    self.vfs2 = self.services.getService(VFSService).get.vfs2
    self.workspace = self.services.getService(Workspace).get
    discard self.workspace.onWorkspaceFolderAdded.subscribe (path: string) => asyncSpawn(self.handleWorkspaceFolderAdded(path))

    return ok()

  proc vcsGetVcsForFile(self: VCSService, file: string): Option[VersionControlSystem] =
    result = VersionControlSystem.none
    let absolutePath = self.workspace.getAbsolutePath(file)
    var longestMatch = -1
    for vcs in self.versionControlSystems:
      if file == "@":
        return vcs.some
      if absolutePath.startsWith(vcs.root):
        if vcs.root.len > longestMatch:
          result = vcs.some
          longestMatch = vcs.root.len

  proc getAllVersionControlSystems*(self: VCSService): seq[VersionControlSystem] =
    return self.versionControlSystems
