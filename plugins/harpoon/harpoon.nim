import std/[strformat, json, jsonutils, strutils, tables, macros, genasts, streams, sequtils, sets, os, terminal, colors, algorithm, unicode]
import util, custom_unicode, myjsonutils, id, wrap, sugar, custom_regex
import api

logCategory = "harpoon"

var files = newSeq[string]()

proc selectFile(index: int) =
  if index in 0..files.high and files[index] != "":
    let res = runCommand(ws"open", ws(files[index]))
    if res.isErr:
      log lvlError, &"selectFile: Failed to open file: {res}"
  else:
    log lvlError, &"selectFile: No file at index {index}"

proc setFile(index: int) =
  let currentFile = runCommand(ws"current-file-path", ws"")
  if currentFile.isErr:
    log lvlError, &"setFile: Failed to get current file path: {currentFile}"
    return
  log lvlInfo, &"Current file: '{currentFile.get}'"
  if files.high < index:
    files.setLen(index + 1)
  files[index] = $currentFile.get

proc showFiles() =
  log lvlInfo, &"showFiles:"
  for i, f in files:
    if f != "":
      log lvlInfo, &"{i}: '{f}'"

proc getSessionData*(name: string, T: typedesc): T =
  try:
    return ($getSessionData(name.ws)).parseJson().jsonTo(T)
  except:
    return T.default

proc saveState() =
  setSessionData(ws"files", stackWitString($files.toJson))

proc loadState() =
  files = getSessionData("files", seq[string])

listenEvent "session/save", proc(event: WitString, payload: WitString) {.cdecl.} =
  saveState()

listenEvent "session/restored", proc(event: WitString, payload: WitString) {.cdecl.} =
  loadState()

setPluginSaveCallback(proc(): string =
  saveState()
  return ""
)

defineCommand(ws("select"),
  active = false,
  docs = ws("Open a file"),
  params = wl[(WitString, WitString)](nil, 0),
  returnType = ws(""),
  context = ws(""),
  data = 0):
  proc(data: uint32, argsString: WitString): WitString {.cdecl.} =
    try:
      let arg = ($argsString).parseJson().jsonTo(int)
      selectFile(arg)
    except CatchableError as e:
      log lvlError, &"Failed to run command 'select': {e.msg}"

    return ws""

defineCommand(ws("set"),
  active = false,
  docs = ws("Set current file"),
  params = wl[(WitString, WitString)](nil, 0),
  returnType = ws(""),
  context = ws(""),
  data = 0):
  proc(data: uint32, argsString: WitString): WitString {.cdecl.} =
    try:
      let arg = ($argsString).parseJson().jsonTo(int)
      setFile(arg)
    except CatchableError as e:
      log lvlError, &"Failed to run command 'select': {e.msg}"

    return ws""

defineCommand(ws("list"),
  active = false,
  docs = ws("Show file list"),
  params = wl[(WitString, WitString)](nil, 0),
  returnType = ws(""),
  context = ws(""),
  data = 0):
  proc(data: uint32, argsString: WitString): WitString {.cdecl.} =
    try:
      showFiles()
    except CatchableError as e:
      log lvlError, &"Failed to run command 'select': {e.msg}"

    return ws""

loadState()
