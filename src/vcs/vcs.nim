import std/[options, strutils, os, sugar, tables]
import misc/[custom_async, custom_logger, util, event]
import text/diff
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

  VersionControlSystem* = ref object of RootObj
    root*: string
    status*: string
    updateStatusImpl*: proc(self: VersionControlSystem) {.gcsafe, raises: [].}
    stageFileImpl*: proc(self: VersionControlSystem, path: string): Future[string] {.gcsafe, async: (raises: []).}
    unstageFileImpl*: proc(self: VersionControlSystem, path: string): Future[string] {.gcsafe, async: (raises: []).}
    revertFileImpl*: proc(self: VersionControlSystem, path: string): Future[string] {.gcsafe, async: (raises: []).}
    getCommittedFileContentImpl*: proc(self: VersionControlSystem, path: string): Future[seq[string]] {.gcsafe, async: (raises: []).}
    getStagedFileContentImpl*: proc(self: VersionControlSystem, path: string): Future[seq[string]] {.gcsafe, async: (raises: []).}
    getWorkingFileContentImpl*: proc(self: VersionControlSystem, path: string): Future[seq[string]] {.gcsafe, async: (raises: []).}
    getFileChangesImpl*: proc(self: VersionControlSystem, path: string, staged: bool = false): Future[Option[seq[LineMapping]]] {.gcsafe, async: (raises: []).}
    checkoutFileImpl*: proc(self: VersionControlSystem, path: string): Future[string] {.gcsafe, async: (raises: []).}
    addFileImpl*: proc(self: VersionControlSystem, path: string): Future[string] {.gcsafe, async: (raises: []).}
    getChangedFilesImpl*: proc(self: VersionControlSystem): Future[seq[VCSFileInfo]] {.gcsafe, async: (raises: []).}

type
  VCSDetector* = proc(rootDir: string): Option[VersionControlSystem] {.gcsafe, raises: [].}

  VCSService* = ref object of Service
    config*: ConfigService
    workspace*: Workspace
    versionControlSystems*: seq[VersionControlSystem]
    vfs*: VFS
    detectors*: Table[string, VCSDetector]

func serviceName*(_: typedesc[VCSService]): string = "VCSService"

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

proc getCommittedFileContent*(self: VersionControlSystem, path: string): Future[seq[string]] {.gcsafe, async: (raises: []).} =
  if self.getCommittedFileContentImpl != nil:
    return await self.getCommittedFileContentImpl(self, path)

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

proc getChangedFiles*(self: VersionControlSystem): Future[seq[VCSFileInfo]] {.gcsafe, async: (raises: []).} =
  if self.getChangedFilesImpl != nil:
    return await self.getChangedFilesImpl(self)

when implModule:
  addBuiltinService(VCSService, Workspace, ConfigService, VFSService)

  func isUntracked*(fileInfo: VCSFileInfo): bool = fileInfo.unstagedStatus == Untracked

  proc handleWorkspaceFolderAdded(self: VCSService, path: string) {.async: (raises: []).} =
    try:
      for detector in self.detectors.values:
        if detector(path).getSome(vcs):
          self.versionControlSystems.add vcs

    except CatchableError as e:
      log lvlError, &"Failed to detect version control systems: {e.msg}\n{e.getStackTrace()}"

  method init*(self: VCSService): Future[Result[void, ref CatchableError]] {.async: (raises: []).} =
    log lvlInfo, &"VCSService.init"
    self.config = self.services.getService(ConfigService).get
    self.vfs = self.services.getService(VFSService).get.vfs
    self.workspace = self.services.getService(Workspace).get
    discard self.workspace.onWorkspaceFolderAdded.subscribe (path: string) => asyncSpawn(self.handleWorkspaceFolderAdded(path))

    return ok()

  proc getVcsForFile*(self: VCSService, file: string): Option[VersionControlSystem] =
    let absolutePath = self.workspace.getAbsolutePath(file)
    for vcs in self.versionControlSystems:
      if absolutePath.startsWith(vcs.root):
        return vcs.some
    return VersionControlSystem.none

  proc getAllVersionControlSystems*(self: VCSService): seq[VersionControlSystem] =
    return self.versionControlSystems
