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
  import misc/[delayed_task]
  import text/diff
  import service, config_provider

  logCategory "vsc-perforce"

  type
    VersionControlSystemPerforce* = ref object of VersionControlSystem
      workspaceRoot: string
      client: string
      stream: string
      settings: ConfigStore
      updateStatusTask: DelayedTask

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

    if self.client != "":
      self.status = self.client
    else:
      self.status = "No client"

  proc perforceUpdateStatus(self: VersionControlSystemPerforce): Future[void] {.gcsafe, async: (raises: []).} =
    try:
      var args = @["info"]

      const clientStreamName = "Client stream: "

      var stream = "?"

      let lines = runProcessAsync("p4", args, workingDir=self.root, log = false).await
      for line in lines:
        if line.startsWith(clientStreamName):
          stream = line[clientStreamName.len..^1]

      self.stream = stream

      if self.client != "":
        self.status = &"{self.stream}  {self.client}"
      else:
        self.status = "No client"

    except CatchableError as e:
      log lvlWarn, &"Failed to update perforce status: {e.msg}"

  proc parseFileStatusPerforce(action: string): VCSFileStatus =
    result = case action
    of "edit": Modified
    of "add": Added
    of "delete": Deleted
    of "branch": Added
    of "integrate": Modified
    else: None

  proc parseUnifiedDiffRange(s: string): Option[(int, int)] =
    try:
      if s.contains(','):
        let parts = s[1..^1].split(',')
        let first = parts[0].parseInt - 1
        let count = parts[1].parseInt
        return (first, first + count).some
      else:
        let first = s[1..^1].parseInt - 1
        return (first, first + 1).some
    except CatchableError:
      return (int, int).none

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

  proc perforceGetChangedFiles(self: VersionControlSystemPerforce): Future[seq[VCSChangelist]] {.gcsafe, async: (raises: []).} =

    try:
      let lines = runProcessAsync("p4", @["opened"], workingDir=self.root).await

      # Map changelist ID -> files
      var changelistMap = initTable[string, seq[VCSFileInfo]]()

      for line in lines:
        # Format: //depot/path/to/file#rev - action changelist# change (type)
        # or: //depot/path/to/file#rev - action default change (type)
        let parts = line.split(" - ")
        if parts.len < 2:
          continue

        let filePart = parts[0]
        let actionPart = parts[1]

        # Extract depot path
        let hashIdx = filePart.find('#')
        if hashIdx < 0:
          continue
        let depotPath = filePart[0..<hashIdx]

        # Extract action and changelist number
        # Format: "action change changelist# (type)" or "action default change (type)"
        let actionParts = actionPart.split(" ")
        if actionParts.len < 3:
          continue
        let action = actionParts[0]

        # Check if it's default changelist or numbered changelist
        var changelistId = ""
        if actionParts[1] == "default":
          changelistId = "default"
        elif actionParts[1] == "change" and actionParts.len >= 3:
          # Format: "action change changelist# (type)"
          changelistId = actionParts[2]
        else:
          continue

        let status = parseFileStatusPerforce(action)

        # Convert depot path to local path by replacing the stream prefix with the workspace root
        if self.stream != "" and depotPath.startsWith(self.stream):
          let relativePath = depotPath[self.stream.len..^1]
          let localPath = (self.workspaceRoot & relativePath).normalizePathUnix
          let fileInfo = VCSFileInfo(
            stagedStatus: None,
            unstagedStatus: status,
            path: localPath
          )

          if not changelistMap.hasKey(changelistId):
            changelistMap[changelistId] = newSeq[VCSFileInfo]()
          changelistMap[changelistId].add fileInfo

      # Get descriptions for each changelist
      var changelists = newSeq[VCSChangelist]()

      for changelistId, files in changelistMap.pairs:
        var description = ""
        var author = ""

        if changelistId == "default":
          description = "Default changelist"
        else:
          # Get changelist description using p4 describe
          try:
            let describeLines = runProcessAsync("p4", @["describe", "-s", changelistId], workingDir=self.root).await
            if describeLines.len > 0:
              # First line format: "Change 12345 by user@client on date/time"
              let firstLine = describeLines[0]
              if firstLine.startsWith("Change "):
                let byIdx = firstLine.find(" by ")
                if byIdx >= 0:
                  let atIdx = firstLine.find("@", byIdx)
                  if atIdx >= 0:
                    author = firstLine[byIdx + 4..<atIdx]

              # Description starts after blank line
              var inDescription = false
              var descLines = newSeq[string]()
              for line in describeLines:
                if line.len == 0:
                  inDescription = true
                  continue
                if inDescription:
                  # Description lines are indented with a tab
                  if line.startsWith("\t"):
                    descLines.add line[1..^1]
                  elif line.startsWith("Affected files") or line.startsWith("Differences"):
                    break
                  else:
                    descLines.add line

              description = descLines.join(" ").strip()
              if description == "":
                description = &"Changelist {changelistId}"
          except CatchableError as e:
            log lvlError, &"Failed to get changelist description for {changelistId}: {e.msg}"
            description = &"Changelist {changelistId}"

        changelists.add VCSChangelist(
          id: changelistId,
          description: description,
          author: author,
          files: files
        )

      return changelists
    except CatchableError as e:
      log lvlError, &"Failed to get changed files: {e.msg}"
      return @[]

  proc perforceGetCommittedFileContent(self: VersionControlSystemPerforce, path: string, commit: string = ""): Future[seq[string]] {.gcsafe, async: (raises: []).} =
    try:
      let args = @["print", "-q", path & "#have"]
      log lvlInfo, fmt"getCommittedFileContent: '{path}' -- {args}"
      let lines = runProcessAsync("p4", args, workingDir=self.root).await
      # Strip trailing \r from lines to match local file format
      var res = newSeq[string](lines.len)
      for i, line in lines:
        if line.len > 0 and line[^1] == '\r':
          res[i] = line[0..^2]
        else:
          res[i] = line
      return res
    except CatchableError:
      return @[]

  proc perforceGetStagedFileContent(self: VersionControlSystemPerforce, path: string): Future[seq[string]] {.gcsafe, async: (raises: []).} =
    try:
      let args = @["print", "-q", path & "#have"]
      log lvlInfo, fmt"getStagedFileContent: '{path}' -- {args}"
      let lines = runProcessAsync("p4", args, workingDir=self.root).await
      # Strip trailing \r from lines to match local file format
      var res = newSeq[string](lines.len)
      for i, line in lines:
        if line.len > 0 and line[^1] == '\r':
          res[i] = line[0..^2]
        else:
          res[i] = line
      return res
    except CatchableError:
      return @[]

  proc perforceGetWorkingFileContent(self: VersionControlSystemPerforce, path: string): Future[seq[string]] {.gcsafe, async: (raises: []).} =
    try:
      log lvlInfo, fmt"getWorkingFileContent '{path}'"
      var lines = newSeq[string]()
      for line in lines(path):
        lines.add line
      return lines
    except CatchableError:
      return @[]

  proc perforceGetFileChanges(self: VersionControlSystemPerforce, path: string, staged: bool = false):
      Future[Option[seq[LineMapping]]] {.gcsafe, async: (raises: []).} =
    try:
      var args = @["diff", "-du0", "-dl"]

      let extraArgs = self.settings.get("vcs.perforce.diff-args", newSeq[string]())
      args.add extraArgs
      args.add path

      log lvlInfo, fmt"getFileChanges: '{path}' -- {args}"

      let lines = runProcessAsync("p4", args, workingDir=self.root).await

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

        if deletedRaw.len == 0 or deletedRaw[0] != '-':
          log lvlError, &"Failed to handle removed line in p4 diff: '{line}'"
          return seq[LineMapping].none
        if addedRaw.len == 0 or addedRaw[0] != '+':
          log lvlError, &"Failed to handle added line in p4 diff: '{line}'"
          return seq[LineMapping].none

        let deletedRange = parseUnifiedDiffRange(deletedRaw)
        if deletedRange.isNone:
          log lvlError, &"Failed to parse deleted range: '{deletedRaw}'"
          return seq[LineMapping].none

        let addedRange = parseUnifiedDiffRange(addedRaw)
        if addedRange.isNone:
          log lvlError, &"Failed to parse added range: '{addedRaw}'"
          return seq[LineMapping].none

        current = LineMapping(
          source: deletedRange.get,
          target: addedRange.get,
        ).some

      if current.isSome:
        mappings.add current.get.move
        current = LineMapping.none

      return mappings.some
    except CatchableError as e:
      log lvlError, &"Failed to get file changes: {e.msg}"
      return seq[LineMapping].none

  proc newVersionControlSystemPerforce*(root: string): VersionControlSystemPerforce =
    new result
    result.name = "Perforce"
    result.root = root
    result.updateStatusImpl = proc(self: VersionControlSystem) {.gcsafe, raises: [].} =
      asyncSpawn self.VersionControlSystemPerforce.perforceUpdateStatus()
    result.getChangedFilesImpl = proc(self: VersionControlSystem): Future[seq[VCSChangelist]] {.gcsafe, async: (raises: []).} =
      return await self.VersionControlSystemPerforce.perforceGetChangedFiles()
    result.revertFileImpl = proc(self: VersionControlSystem, path: string): Future[string] {.gcsafe, async: (raises: []).} =
      return await self.VersionControlSystemPerforce.perforceRevertFile(path)
    result.getCommittedFileContentImpl = proc(self: VersionControlSystem, path: string, commit: string = ""): Future[seq[string]] {.gcsafe, async: (raises: []).} =
      return await self.VersionControlSystemPerforce.perforceGetCommittedFileContent(path, commit)
    result.getStagedFileContentImpl = proc(self: VersionControlSystem, path: string): Future[seq[string]] {.gcsafe, async: (raises: []).} =
      return await self.VersionControlSystemPerforce.perforceGetStagedFileContent(path)
    result.getWorkingFileContentImpl = proc(self: VersionControlSystem, path: string): Future[seq[string]] {.gcsafe, async: (raises: []).} =
      return await self.VersionControlSystemPerforce.perforceGetWorkingFileContent(path)
    result.checkoutFileImpl = proc(self: VersionControlSystem, path: string): Future[string] {.gcsafe, async: (raises: []).} =
      return await self.VersionControlSystemPerforce.perforceCheckoutFile(path)
    result.addFileImpl = proc(self: VersionControlSystem, path: string): Future[string] {.gcsafe, async: (raises: []).} =
      return await self.VersionControlSystemPerforce.perforceAddFile(path)
    result.getFileChangesImpl = proc(self: VersionControlSystem, path: string, staged: bool = false): Future[Option[seq[LineMapping]]] {.gcsafe, async: (raises: []).} =
      return await self.VersionControlSystemPerforce.perforceGetFileChanges(path, staged)

    let self = result
    asyncSpawn self.detectClientAsync()

    let services = getServices()
    if services == nil:
      return

    let config = services.getService(ConfigService).get.runtime
    self.settings = config

    asyncSpawn self.perforceUpdateStatus()
    self.updateStatusTask = startDelayed(config.get("perforce.update-status-interval", 10000), true):
      self.updateStatusTask.interval = config.get("perforce.update-status-interval", 10000).int64
      asyncSpawn self.perforceUpdateStatus()

  proc detectPerforce(path: string): seq[VersionControlSystem] =
    if fileExists(path // ".p4ignore"):
      log lvlInfo, fmt"Found perforce repository in {path}"
      let vcs = newVersionControlSystemPerforce(path)
      return @[vcs.VersionControlSystem]

  proc init_module_vcs_perforce*() {.cdecl, exportc, dynlib.} =
    let services = getServices()
    if services == nil:
      log lvlWarn, &"Failed to initialize init_module_vcs_perforce: no services found"
      return

    let vcs = services.getService(VCSService).get
    vcs.detectors["perforce"] = detectPerforce
