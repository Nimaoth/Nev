import std/[options, strutils, os, sugar]
import misc/[custom_async, custom_logger, util, event]
import text/diff
import workspaces/workspace
import service, config_provider, vfs, vfs_service

{.push gcsafe.}
{.push raises: [].}

logCategory "vcs"

type
  VCSFileStatus* = enum None = ".", Modified = "M", Added = "A", Deleted = "D", Untracked = "?"
  VCSFileInfo* = object
    stagedStatus*: VCSFileStatus
    unstagedStatus*: VCSFileStatus
    path*: string

  VersionControlSystem* = ref object of RootObj
    root*: string

type
  VCSService* = ref object of Service
    config*: ConfigService
    workspace*: Workspace
    versionControlSystems*: seq[VersionControlSystem]
    vfs*: VFS

func serviceName*(_: typedesc[VCSService]): string = "VCSService"
addBuiltinService(VCSService, Workspace, ConfigService, VFSService)

func isUntracked*(fileInfo: VCSFileInfo): bool = fileInfo.unstagedStatus == Untracked

method getChangedFiles*(self: VersionControlSystem): Future[seq[VCSFileInfo]] {.base.} =
  newSeq[VCSFileInfo]().toFuture

method stageFile*(self: VersionControlSystem, path: string): Future[string] {.base.} = "".toFuture
method unstageFile*(self: VersionControlSystem, path: string): Future[string] {.base.} = "".toFuture
method revertFile*(self: VersionControlSystem, path: string): Future[string] {.base.} = "".toFuture

method getCommittedFileContent*(self: VersionControlSystem, path: string): Future[seq[string]] {.base.} =
  newSeq[string]().toFuture

method getStagedFileContent*(self: VersionControlSystem, path: string): Future[seq[string]] {.base.} =
  newSeq[string]().toFuture

method getWorkingFileContent*(self: VersionControlSystem, path: string): Future[seq[string]] {.base.} =
  newSeq[string]().toFuture

method getFileChanges*(self: VersionControlSystem, path: string, staged: bool = false):
    Future[Option[seq[LineMapping]]] {.base.} =
  seq[LineMapping].none.toFuture

method checkoutFile*(self: VersionControlSystem, path: string): Future[string] {.base.} = "".toFuture

import vcs_git, vcs_perforce

proc detectVersionControlSystemIn(self: VCSService, path: string): Option[VersionControlSystem] =
  if dirExists(path // ".git"):
    log lvlInfo, fmt"Found git repository in {path}"
    let vcs = newVersionControlSystemGit(path, self.config.runtime)
    return vcs.VersionControlSystem.some

  if fileExists(path // ".p4ignore"):
    log lvlInfo, fmt"Found perforce repository in {path}"
    let vcs = newVersionControlSystemPerforce(path)
    return vcs.VersionControlSystem.some

proc handleWorkspaceFolderAdded(self: VCSService, path: string) {.async: (raises: []).} =
  try:
    if self.detectVersionControlSystemIn(path).getSome(vcs):
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
