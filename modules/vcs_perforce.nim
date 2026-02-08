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

  logCategory "vsc-perforce"

  type
    VersionControlSystemPerforce* = ref object of VersionControlSystem
      workspaceRoot: string
      client: string

  iterator tokens(s: string, seps: set[char] = Whitespace): tuple[i: int, strIndex: int, token: string] =
    var strIndex = 0
    var i = 0
    while true:
      var endIndex = strIndex
      var isSep = endIndex < s.len and s[endIndex] in seps
      while endIndex < s.len and (s[endIndex] in seps) == isSep: inc(endIndex)
      if endIndex > strIndex:
        if not isSep:
          yield (i, strIndex, substr(s, strIndex, endIndex - 1))
          inc i
      else:
        break
      strIndex = endIndex

  proc detectClientAsync(self: VersionControlSystemPerforce) {.async.} =
    let stats = await runProcessAsync("p4", @["info"])

    var host = ""

    for stat in stats:
      const hostPrefix = "Client host: "
      if stat.startsWith(hostPrefix):
        host = stat[hostPrefix.len..^1]

    log lvlInfo, &"[detectClient] Host: '{host}'"

    let clients = await runProcessAsync("p4", @["clients"])

    for client in clients:
      if not client.startsWith("Client "):
        continue

      if not client.contains(host):
        continue

      let createdByIndex = client.find(" 'Created by")
      if createdByIndex < 0:
        continue

      var clientName = ""
      var workspaceRoot = ""
      for (i, strIndex, token) in client[0..<createdByIndex].tokens:
        if i == 1:
          clientName = token
        elif i == 4:
          workspaceRoot = client[strIndex..<createdByIndex]
          break

      if clientName == "" or workspaceRoot == "":
        continue

      workspaceRoot = workspaceRoot.normalizePathUnix

      if self.root.startsWith(workspaceRoot):
        log lvlInfo, &"Found client for root '{self.root}': {clientName}"
        self.client = clientName
        self.workspaceRoot = workspaceRoot
        break

    if self.client == "":
      log lvlError, &"Failed to find client info from root directory"

  proc perforceCheckoutFile*(self: VersionControlSystemPerforce, path: string): Future[string] {.gcsafe, async: (raises: []).} =
    try:
      let command = "powershell"
      let args = @[
        "-NoProfile",
        "-Command",
        fmt"p4 set P4CLIENT={self.client}; p4 edit {path}"
      ]

      log lvlInfo, fmt"edit file: '{command} {args}'"
      return runProcessAsync(command, args, workingDir=self.root).await.join(" ")
    except CatchableError:
      return ""

  proc perforceAddFile*(self: VersionControlSystemPerforce, path: string): Future[string] {.gcsafe, async: (raises: []).} =
    try:
      let command = "powershell"
      let args = @[
        "-NoProfile",
        "-Command",
        fmt"p4 set P4CLIENT={self.client}; p4 add {path}"
      ]

      log lvlInfo, fmt"add file: '{command} {args}'"
      return runProcessAsync(command, args, workingDir=self.root).await.join(" ")
    except CatchableError:
      return ""

  proc perforceRevertFile*(self: VersionControlSystemPerforce, path: string): Future[string] {.gcsafe, async: (raises: []).} =
    try:
      let command = "powershell"
      let args = @[
        "-NoProfile",
        "-Command",
        fmt"p4 set P4CLIENT={self.client}; p4 revert {path}"
      ]

      log lvlInfo, fmt"revert file: '{command} {args}'"
      return runProcessAsync(command, args, workingDir=self.root).await.join(" ")
    except CatchableError:
      return ""

  proc newVersionControlSystemPerforce*(root: string): VersionControlSystemPerforce =
    new result
    result.root = root
    # result.updateStatusImpl = proc(self: VersionControlSystem) {.gcsafe, raises: [].} =
    #   asyncSpawn self.VersionControlSystemPerforce.perforceUpdateStatus()
    # result.getChangedFilesImpl = proc(self: VersionControlSystem): Future[seq[VCSFileInfo]] {.gcsafe, async: (raises: []).} =
    #   return await self.VersionControlSystemPerforce.perforceGetChangedFiles()
    # result.stageFileImpl = proc(self: VersionControlSystem, path: string): Future[string] {.gcsafe, async: (raises: []).} =
    #   return await self.VersionControlSystemPerforce.perforceStageFile(path)
    # result.unstageFileImpl = proc(self: VersionControlSystem, path: string): Future[string] {.gcsafe, async: (raises: []).} =
    #   return await self.VersionControlSystemPerforce.perforceUnstageFile(path)
    result.revertFileImpl = proc(self: VersionControlSystem, path: string): Future[string] {.gcsafe, async: (raises: []).} =
      return await self.VersionControlSystemPerforce.perforceRevertFile(path)
    # result.getCommittedFileContentImpl = proc(self: VersionControlSystem, path: string): Future[seq[string]] {.gcsafe, async: (raises: []).} =
    #   return await self.VersionControlSystemPerforce.perforceGetCommittedFileContent(path)
    # result.getStagedFileContentImpl = proc(self: VersionControlSystem, path: string): Future[seq[string]] {.gcsafe, async: (raises: []).} =
    #   return await self.VersionControlSystemPerforce.perforceGetStagedFileContent(path)
    # result.getWorkingFileContentImpl = proc(self: VersionControlSystem, path: string): Future[seq[string]] {.gcsafe, async: (raises: []).} =
    #   return await self.VersionControlSystemPerforce.perforceGetWorkingFileContent(path)
    # result.getFileChangesImpl = proc(self: VersionControlSystem, path: string, staged: bool = false): Future[Option[seq[LineMapping]]] {.gcsafe, async: (raises: []).} =
    #   return await self.VersionControlSystemPerforce.perforceGetFileChanges(path, staged)

    let self = result
    asyncSpawn self.detectClientAsync()

  proc detectPerforce(path: string): Option[VersionControlSystem] =
    if fileExists(path // ".p4ignore"):
      log lvlInfo, fmt"Found perforce repository in {path}"
      let vcs = newVersionControlSystemPerforce(path)
      return vcs.VersionControlSystem.some

  proc init_module_vcs_perforce*() {.cdecl, exportc, dynlib.} =
    let services = getServices()
    if services == nil:
      log lvlWarn, &"Failed to initialize init_module_vcs_perforce: no services found"
      return

    let vcs = services.getService(VCSService).get
    vcs.detectors["perforce"] = detectPerforce
