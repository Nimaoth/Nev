import std/[strutils, strformat]
import misc/[async_process, custom_async, util, custom_logger]
import platform/filesystem
import vcs

{.push gcsafe.}
{.push raises: [].}

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

proc newVersionControlSystemPerforce*(root: string): VersionControlSystemPerforce =
  new result
  result.root = root

  let self = result
  asyncSpawn self.detectClientAsync()

method checkoutFile*(self: VersionControlSystemPerforce, path: string): Future[string] {.async.} =
  let command = "powershell"
  let args = @[
    "-NoProfile",
    "-Command",
    fmt"p4 set P4CLIENT={self.client}; p4 edit {path}"
  ]

  log lvlInfo, fmt"edit file: '{command} {args}'"
  return runProcessAsync(command, args, workingDir=self.root).await.join(" ")

method revertFile*(self: VersionControlSystemPerforce, path: string): Future[string] {.async.} =
  let command = "powershell"
  let args = @[
    "-NoProfile",
    "-Command",
    fmt"p4 set P4CLIENT={self.client}; p4 revert {path}"
  ]

  log lvlInfo, fmt"revert file: '{command} {args}'"
  return runProcessAsync(command, args, workingDir=self.root).await.join(" ")