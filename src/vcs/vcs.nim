import std/[options]
import misc/[custom_async]
import text/diff

type

  VCSFileStatus* = enum None = ".", Modified = "M", Added = "A", Deleted = "D", Untracked = "?"
  VCSFileInfo* = object
    stagedStatus*: VCSFileStatus
    unstagedStatus*: VCSFileStatus
    path*: string

  VersionControlSystem* = ref object of RootObj
    root*: string

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
