import std/[options, strutils, os]
import misc/[custom_async, custom_logger, util]
import text/diff
import workspaces/workspace
import platform/[filesystem]
import service, config_provider

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
    fs*: Filesystem

func serviceName*(_: typedesc[VCSService]): string = "VCSService"
addBuiltinService(VCSService, WorkspaceService, ConfigService)

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

proc detectVersionControlSystemIn(path: string): Option[VersionControlSystem] =
  if dirExists(path // ".git"):
    log lvlInfo, fmt"Found git repository in {path}"
    let vcs = newVersionControlSystemGit(path)
    return vcs.VersionControlSystem.some

  if fileExists(path // ".p4ignore"):
    log lvlInfo, fmt"Found perforce repository in {path}"
    let vcs = newVersionControlSystemPerforce(path)
    return vcs.VersionControlSystem.some

proc waitForWorkspace(self: VCSService) {.async: (raises: []).} =
  let workspaceService = self.services.getService(WorkspaceService).get
  while workspaceService.workspace.isNil:
    try:
      sleepAsync(10.milliseconds).await
    except CancelledError:
      discard

  self.workspace = workspaceService.workspace

  try:
    let info = self.workspace.info.await

    for (path, _) in info.folders:
      if detectVersionControlSystemIn(path).getSome(vcs):
        self.versionControlSystems.add vcs
  except CatchableError as e:
    log lvlError, &"Failed to detect version control systems: {e.msg}\n{e.getStackTrace()}"


method init*(self: VCSService): Future[Result[void, ref CatchableError]] {.async: (raises: []).} =
  log lvlInfo, &"VCSService.init"
  self.config = self.services.getService(ConfigService).get
  self.fs = ({.gcsafe.}: fs)
  asyncSpawn self.waitForWorkspace()

  return ok()

proc getVcsForFile*(self: VCSService, file: string): Option[VersionControlSystem] =
  let absolutePath = self.workspace.getAbsolutePath(file)
  for vcs in self.versionControlSystems:
    if absolutePath.startsWith(vcs.root):
      return vcs.some
  return VersionControlSystem.none

proc getAllVersionControlSystems*(self: VCSService): seq[VersionControlSystem] =
  return self.versionControlSystems
