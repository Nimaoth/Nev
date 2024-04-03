import std/[strutils, sequtils, strformat, os, tables, options, enumutils]

import misc/[async_process, custom_async, util]
import scripting_api

proc listUHTFolders(base: string) =
  for (kind, file) in walkDir(base):
    case kind
    of pcDir:
      echo (&"    - \"-I{file}/UHT\"").replace("\\", "/")
    else:
      discard

# listUHTFolders "C:/Program Files/Epic Games/UE_5.3/Engine/Intermediate/Build/Win64/UnrealEditor/Inc"
# listUHTFolders "D:/dev/Unreal/EditorPlugin/Intermediate/Build/Win64/UnrealEditor/Inc"
# listUHTFolders "D:/dev/Unreal/EditorPlugin/Plugins/AbsytreeUE/Intermediate/Build/Win64/UnrealEditor/Inc"
proc readAllLines(p: AsyncProcess) {.async.} =
  while true:
    let line = p.recvLine.await
    echo "> ", line

proc test() {.async.} =
  var p = startAsyncProcess("test2.exe", [])

  asyncCheck p.readAllLines()

  while true:
    echo "tick"
    await sleepAsync(1)

asyncCheck test()

while hasPendingOperations():
  poll(5)

