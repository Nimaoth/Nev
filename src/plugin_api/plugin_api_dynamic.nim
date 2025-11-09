import std/[options, json, jsonutils, tables]
import plugin_api, lisp

{.used.}

proc getArg(args: LispVal, namedArgs: LispVal, index: int, name: string, T: typedesc): T =
  if args != nil and index < args.elems.len:
    return args.elems[index].toJson().jsonTo(T)
  if namedArgs != nil and name in namedArgs.fields:
    return namedArgs.fields[name].toJson().jsonTo(T)
  return T.default

proc coreApiVersion*(instance: ptr InstanceData, args: LispVal, namedArgs: LispVal): LispVal =
  let res = instance.coreApiVersion()
  return res.toJson().jsonTo(LispVal)
proc coreGetTime*(instance: ptr InstanceData, args: LispVal, namedArgs: LispVal): LispVal =
  let res = instance.coreGetTime()
  return res.toJson().jsonTo(LispVal)
proc coreGetPlatform*(instance: ptr InstanceData, args: LispVal, namedArgs: LispVal): LispVal =
  let res = instance.coreGetPlatform()
  return res.toJson().jsonTo(LispVal)
proc coreIsMainThread*(instance: ptr InstanceData, args: LispVal, namedArgs: LispVal): LispVal =
  let res = instance.coreIsMainThread()
  return res.toJson().jsonTo(LispVal)
proc coreGetArguments*(instance: ptr InstanceData, args: LispVal, namedArgs: LispVal): LispVal =
  let res = instance.coreGetArguments()
  return res.toJson().jsonTo(LispVal)
proc coreSpawnBackground*(instance: ptr InstanceData, args: LispVal, namedArgs: LispVal): LispVal =
  instance.coreSpawnBackground(getArg(args, namedArgs, 0, "args", string), getArg(args, namedArgs, 1, "executor", plugin_api.BackgroundExecutor), )
  return newNil()
proc coreFinishBackground*(instance: ptr InstanceData, args: LispVal, namedArgs: LispVal): LispVal =
  instance.coreFinishBackground()
  return newNil()
proc commandsDefineCommand*(instance: ptr InstanceData, args: LispVal, namedArgs: LispVal): LispVal =
  instance.commandsDefineCommand(getArg(args, namedArgs, 0, "name", string), getArg(args, namedArgs, 1, "active", bool), getArg(args, namedArgs, 2, "docs", string), getArg(args, namedArgs, 3, "params", seq[(string, string, )]), getArg(args, namedArgs, 4, "returntype", string), getArg(args, namedArgs, 5, "context", string), getArg(args, namedArgs, 6, "fun", uint32), getArg(args, namedArgs, 7, "data", uint32), )
  return newNil()
proc commandsRunCommand*(instance: ptr InstanceData, args: LispVal, namedArgs: LispVal): LispVal =
  let res = instance.commandsRunCommand(getArg(args, namedArgs, 0, "name", string), getArg(args, namedArgs, 1, "arguments", string), )
  return res.toJson().jsonTo(LispVal)
proc commandsExitCommandLine*(instance: ptr InstanceData, args: LispVal, namedArgs: LispVal): LispVal =
  instance.commandsExitCommandLine()
  return newNil()
proc settingsGetSettingRaw*(instance: ptr InstanceData, args: LispVal, namedArgs: LispVal): LispVal =
  let res = instance.settingsGetSettingRaw(getArg(args, namedArgs, 0, "name", string), )
  return res.toJson().jsonTo(LispVal)
proc settingsSetSettingRaw*(instance: ptr InstanceData, args: LispVal, namedArgs: LispVal): LispVal =
  instance.settingsSetSettingRaw(getArg(args, namedArgs, 0, "name", string), getArg(args, namedArgs, 1, "value", string), )
  return newNil()
proc editorActiveEditor*(instance: ptr InstanceData, args: LispVal, namedArgs: LispVal): LispVal =
  let res = instance.editorActiveEditor(getArg(args, namedArgs, 0, "options", plugin_api.ActiveEditorFlags), )
  return res.toJson().jsonTo(LispVal)
proc editorGetDocument*(instance: ptr InstanceData, args: LispVal, namedArgs: LispVal): LispVal =
  let res = instance.editorGetDocument(getArg(args, namedArgs, 0, "editor", plugin_api.Editor), )
  return res.toJson().jsonTo(LispVal)
proc textEditorActiveTextEditor*(instance: ptr InstanceData, args: LispVal, namedArgs: LispVal): LispVal =
  let res = instance.textEditorActiveTextEditor(getArg(args, namedArgs, 0, "options", plugin_api.ActiveEditorFlags), )
  return res.toJson().jsonTo(LispVal)
proc textEditorGetDocument*(instance: ptr InstanceData, args: LispVal, namedArgs: LispVal): LispVal =
  let res = instance.textEditorGetDocument(getArg(args, namedArgs, 0, "editor", plugin_api.TextEditor), )
  return res.toJson().jsonTo(LispVal)
proc textEditorAsTextEditor*(instance: ptr InstanceData, args: LispVal, namedArgs: LispVal): LispVal =
  let res = instance.textEditorAsTextEditor(getArg(args, namedArgs, 0, "editor", plugin_api.Editor), )
  return res.toJson().jsonTo(LispVal)
proc textEditorAsTextDocument*(instance: ptr InstanceData, args: LispVal, namedArgs: LispVal): LispVal =
  let res = instance.textEditorAsTextDocument(getArg(args, namedArgs, 0, "document", plugin_api.Document), )
  return res.toJson().jsonTo(LispVal)
proc textEditorCommand*(instance: ptr InstanceData, args: LispVal, namedArgs: LispVal): LispVal =
  let res = instance.textEditorCommand(getArg(args, namedArgs, 0, "editor", plugin_api.TextEditor), getArg(args, namedArgs, 1, "name", string), getArg(args, namedArgs, 2, "arguments", string), )
  return res.toJson().jsonTo(LispVal)
proc textEditorRecordCurrentCommand*(instance: ptr InstanceData, args: LispVal, namedArgs: LispVal): LispVal =
  instance.textEditorRecordCurrentCommand(getArg(args, namedArgs, 0, "editor", plugin_api.TextEditor), getArg(args, namedArgs, 1, "registers", seq[string]), )
  return newNil()
proc textEditorHideCompletions*(instance: ptr InstanceData, args: LispVal, namedArgs: LispVal): LispVal =
  instance.textEditorHideCompletions(getArg(args, namedArgs, 0, "editor", plugin_api.TextEditor), )
  return newNil()
proc textEditorScrollToCursor*(instance: ptr InstanceData, args: LispVal, namedArgs: LispVal): LispVal =
  instance.textEditorScrollToCursor(getArg(args, namedArgs, 0, "editor", plugin_api.TextEditor), getArg(args, namedArgs, 1, "behaviour", Option[plugin_api.ScrollBehaviour]), getArg(args, namedArgs, 2, "relative-position", float32), )
  return newNil()
proc textEditorSetNextSnapBehaviour*(instance: ptr InstanceData, args: LispVal, namedArgs: LispVal): LispVal =
  instance.textEditorSetNextSnapBehaviour(getArg(args, namedArgs, 0, "editor", plugin_api.TextEditor), getArg(args, namedArgs, 1, "behaviour", plugin_api.ScrollSnapBehaviour), )
  return newNil()
proc textEditorUpdateTargetColumn*(instance: ptr InstanceData, args: LispVal, namedArgs: LispVal): LispVal =
  instance.textEditorUpdateTargetColumn(getArg(args, namedArgs, 0, "editor", plugin_api.TextEditor), )
  return newNil()
proc textEditorGetUsage*(instance: ptr InstanceData, args: LispVal, namedArgs: LispVal): LispVal =
  let res = instance.textEditorGetUsage(getArg(args, namedArgs, 0, "editor", plugin_api.TextEditor), )
  return res.toJson().jsonTo(LispVal)
proc textEditorGetRevision*(instance: ptr InstanceData, args: LispVal, namedArgs: LispVal): LispVal =
  let res = instance.textEditorGetRevision(getArg(args, namedArgs, 0, "editor", plugin_api.TextEditor), )
  return res.toJson().jsonTo(LispVal)
proc textEditorSetMode*(instance: ptr InstanceData, args: LispVal, namedArgs: LispVal): LispVal =
  instance.textEditorSetMode(getArg(args, namedArgs, 0, "editor", plugin_api.TextEditor), getArg(args, namedArgs, 1, "mode", string), getArg(args, namedArgs, 2, "exclusive", bool), )
  return newNil()
proc textEditorMode*(instance: ptr InstanceData, args: LispVal, namedArgs: LispVal): LispVal =
  let res = instance.textEditorMode(getArg(args, namedArgs, 0, "editor", plugin_api.TextEditor), )
  return res.toJson().jsonTo(LispVal)
proc textEditorModes*(instance: ptr InstanceData, args: LispVal, namedArgs: LispVal): LispVal =
  let res = instance.textEditorModes(getArg(args, namedArgs, 0, "editor", plugin_api.TextEditor), )
  return res.toJson().jsonTo(LispVal)
proc textEditorClearTabStops*(instance: ptr InstanceData, args: LispVal, namedArgs: LispVal): LispVal =
  instance.textEditorClearTabStops(getArg(args, namedArgs, 0, "editor", plugin_api.TextEditor), )
  return newNil()
proc textEditorUndo*(instance: ptr InstanceData, args: LispVal, namedArgs: LispVal): LispVal =
  instance.textEditorUndo(getArg(args, namedArgs, 0, "editor", plugin_api.TextEditor), getArg(args, namedArgs, 1, "checkpoint", string), )
  return newNil()
proc textEditorRedo*(instance: ptr InstanceData, args: LispVal, namedArgs: LispVal): LispVal =
  instance.textEditorRedo(getArg(args, namedArgs, 0, "editor", plugin_api.TextEditor), getArg(args, namedArgs, 1, "checkpoint", string), )
  return newNil()
proc textEditorAddNextCheckpoint*(instance: ptr InstanceData, args: LispVal, namedArgs: LispVal): LispVal =
  instance.textEditorAddNextCheckpoint(getArg(args, namedArgs, 0, "editor", plugin_api.TextEditor), getArg(args, namedArgs, 1, "checkpoint", string), )
  return newNil()
proc textEditorCopy*(instance: ptr InstanceData, args: LispVal, namedArgs: LispVal): LispVal =
  instance.textEditorCopy(getArg(args, namedArgs, 0, "editor", plugin_api.TextEditor), getArg(args, namedArgs, 1, "register", string), getArg(args, namedArgs, 2, "inclusive-end", bool), )
  return newNil()
proc textEditorPaste*(instance: ptr InstanceData, args: LispVal, namedArgs: LispVal): LispVal =
  instance.textEditorPaste(getArg(args, namedArgs, 0, "editor", plugin_api.TextEditor), getArg(args, namedArgs, 1, "selections", seq[plugin_api.Selection]), getArg(args, namedArgs, 2, "register", string), getArg(args, namedArgs, 3, "inclusive-end", bool), )
  return newNil()
proc textEditorAutoShowCompletions*(instance: ptr InstanceData, args: LispVal, namedArgs: LispVal): LispVal =
  instance.textEditorAutoShowCompletions(getArg(args, namedArgs, 0, "editor", plugin_api.TextEditor), )
  return newNil()
proc textEditorToggleLineComment*(instance: ptr InstanceData, args: LispVal, namedArgs: LispVal): LispVal =
  instance.textEditorToggleLineComment(getArg(args, namedArgs, 0, "editor", plugin_api.TextEditor), )
  return newNil()
proc textEditorInsertText*(instance: ptr InstanceData, args: LispVal, namedArgs: LispVal): LispVal =
  instance.textEditorInsertText(getArg(args, namedArgs, 0, "editor", plugin_api.TextEditor), getArg(args, namedArgs, 1, "text", string), getArg(args, namedArgs, 2, "auto-indent", bool), )
  return newNil()
proc textEditorOpenSearchBar*(instance: ptr InstanceData, args: LispVal, namedArgs: LispVal): LispVal =
  instance.textEditorOpenSearchBar(getArg(args, namedArgs, 0, "editor", plugin_api.TextEditor), getArg(args, namedArgs, 1, "query", string), getArg(args, namedArgs, 2, "scroll-to-preview", bool), getArg(args, namedArgs, 3, "select-result", bool), )
  return newNil()
proc textEditorSetSearchQueryFromMove*(instance: ptr InstanceData, args: LispVal, namedArgs: LispVal): LispVal =
  let res = instance.textEditorSetSearchQueryFromMove(getArg(args, namedArgs, 0, "editor", plugin_api.TextEditor), getArg(args, namedArgs, 1, "move", string), getArg(args, namedArgs, 2, "count", int32), getArg(args, namedArgs, 3, "prefix", string), getArg(args, namedArgs, 4, "suffix", string), )
  return res.toJson().jsonTo(LispVal)
proc textEditorSetSearchQuery*(instance: ptr InstanceData, args: LispVal, namedArgs: LispVal): LispVal =
  let res = instance.textEditorSetSearchQuery(getArg(args, namedArgs, 0, "editor", plugin_api.TextEditor), getArg(args, namedArgs, 1, "query", string), getArg(args, namedArgs, 2, "escape-regex", bool), getArg(args, namedArgs, 3, "prefix", string), getArg(args, namedArgs, 4, "suffix", string), )
  return res.toJson().jsonTo(LispVal)
proc textEditorGetSearchQuery*(instance: ptr InstanceData, args: LispVal, namedArgs: LispVal): LispVal =
  let res = instance.textEditorGetSearchQuery(getArg(args, namedArgs, 0, "editor", plugin_api.TextEditor), )
  return res.toJson().jsonTo(LispVal)
proc textEditorApplyMove*(instance: ptr InstanceData, args: LispVal, namedArgs: LispVal): LispVal =
  let res = instance.textEditorApplyMove(getArg(args, namedArgs, 0, "editor", plugin_api.TextEditor), getArg(args, namedArgs, 1, "selection", plugin_api.Selection), getArg(args, namedArgs, 2, "move", string), getArg(args, namedArgs, 3, "count", int32), getArg(args, namedArgs, 4, "wrap", bool), getArg(args, namedArgs, 5, "include-eol", bool), )
  return res.toJson().jsonTo(LispVal)
proc textEditorMultiMove*(instance: ptr InstanceData, args: LispVal, namedArgs: LispVal): LispVal =
  let res = instance.textEditorMultiMove(getArg(args, namedArgs, 0, "editor", plugin_api.TextEditor), getArg(args, namedArgs, 1, "selections", seq[plugin_api.Selection]), getArg(args, namedArgs, 2, "move", string), getArg(args, namedArgs, 3, "count", int32), getArg(args, namedArgs, 4, "wrap", bool), getArg(args, namedArgs, 5, "include-eol", bool), )
  return res.toJson().jsonTo(LispVal)
proc textEditorSetSelection*(instance: ptr InstanceData, args: LispVal, namedArgs: LispVal): LispVal =
  instance.textEditorSetSelection(getArg(args, namedArgs, 0, "editor", plugin_api.TextEditor), getArg(args, namedArgs, 1, "s", plugin_api.Selection), )
  return newNil()
proc textEditorSetSelections*(instance: ptr InstanceData, args: LispVal, namedArgs: LispVal): LispVal =
  instance.textEditorSetSelections(getArg(args, namedArgs, 0, "editor", plugin_api.TextEditor), getArg(args, namedArgs, 1, "s", seq[plugin_api.Selection]), )
  return newNil()
proc textEditorGetSelection*(instance: ptr InstanceData, args: LispVal, namedArgs: LispVal): LispVal =
  let res = instance.textEditorGetSelection(getArg(args, namedArgs, 0, "editor", plugin_api.TextEditor), )
  return res.toJson().jsonTo(LispVal)
proc textEditorGetSelections*(instance: ptr InstanceData, args: LispVal, namedArgs: LispVal): LispVal =
  let res = instance.textEditorGetSelections(getArg(args, namedArgs, 0, "editor", plugin_api.TextEditor), )
  return res.toJson().jsonTo(LispVal)
proc textEditorLineLength*(instance: ptr InstanceData, args: LispVal, namedArgs: LispVal): LispVal =
  let res = instance.textEditorLineLength(getArg(args, namedArgs, 0, "editor", plugin_api.TextEditor), getArg(args, namedArgs, 1, "line", int32), )
  return res.toJson().jsonTo(LispVal)
proc textEditorAddModeChangedHandler*(instance: ptr InstanceData, args: LispVal, namedArgs: LispVal): LispVal =
  let res = instance.textEditorAddModeChangedHandler(getArg(args, namedArgs, 0, "fun", uint32), )
  return res.toJson().jsonTo(LispVal)
proc textEditorGetSettingRaw*(instance: ptr InstanceData, args: LispVal, namedArgs: LispVal): LispVal =
  let res = instance.textEditorGetSettingRaw(getArg(args, namedArgs, 0, "editor", plugin_api.TextEditor), getArg(args, namedArgs, 1, "name", string), )
  return res.toJson().jsonTo(LispVal)
proc textEditorSetSettingRaw*(instance: ptr InstanceData, args: LispVal, namedArgs: LispVal): LispVal =
  instance.textEditorSetSettingRaw(getArg(args, namedArgs, 0, "editor", plugin_api.TextEditor), getArg(args, namedArgs, 1, "name", string), getArg(args, namedArgs, 2, "value", string), )
  return newNil()
proc textEditorEvaluateExpressions*(instance: ptr InstanceData, args: LispVal, namedArgs: LispVal): LispVal =
  instance.textEditorEvaluateExpressions(getArg(args, namedArgs, 0, "editor", plugin_api.TextEditor), getArg(args, namedArgs, 1, "selections", seq[plugin_api.Selection]), getArg(args, namedArgs, 2, "inclusive", bool), getArg(args, namedArgs, 3, "prefix", string), getArg(args, namedArgs, 4, "suffix", string), getArg(args, namedArgs, 5, "add-selection-index", bool), )
  return newNil()
proc textEditorIndent*(instance: ptr InstanceData, args: LispVal, namedArgs: LispVal): LispVal =
  instance.textEditorIndent(getArg(args, namedArgs, 0, "editor", plugin_api.TextEditor), getArg(args, namedArgs, 1, "delta", int32), )
  return newNil()
proc textEditorGetCommandCount*(instance: ptr InstanceData, args: LispVal, namedArgs: LispVal): LispVal =
  let res = instance.textEditorGetCommandCount(getArg(args, namedArgs, 0, "editor", plugin_api.TextEditor), )
  return res.toJson().jsonTo(LispVal)
proc textEditorSetCursorScrollOffset*(instance: ptr InstanceData, args: LispVal, namedArgs: LispVal): LispVal =
  instance.textEditorSetCursorScrollOffset(getArg(args, namedArgs, 0, "editor", plugin_api.TextEditor), getArg(args, namedArgs, 1, "cursor", plugin_api.Cursor), getArg(args, namedArgs, 2, "scroll-offset", float32), )
  return newNil()
proc textEditorGetVisibleLineCount*(instance: ptr InstanceData, args: LispVal, namedArgs: LispVal): LispVal =
  let res = instance.textEditorGetVisibleLineCount(getArg(args, namedArgs, 0, "editor", plugin_api.TextEditor), )
  return res.toJson().jsonTo(LispVal)
proc textEditorCreateAnchors*(instance: ptr InstanceData, args: LispVal, namedArgs: LispVal): LispVal =
  let res = instance.textEditorCreateAnchors(getArg(args, namedArgs, 0, "editor", plugin_api.TextEditor), getArg(args, namedArgs, 1, "selections", seq[plugin_api.Selection]), )
  return res.toJson().jsonTo(LispVal)
proc textEditorResolveAnchors*(instance: ptr InstanceData, args: LispVal, namedArgs: LispVal): LispVal =
  let res = instance.textEditorResolveAnchors(getArg(args, namedArgs, 0, "editor", plugin_api.TextEditor), getArg(args, namedArgs, 1, "anchors", seq[(plugin_api.Anchor, plugin_api.Anchor, )]), )
  return res.toJson().jsonTo(LispVal)
proc textEditorEdit*(instance: ptr InstanceData, args: LispVal, namedArgs: LispVal): LispVal =
  let res = instance.textEditorEdit(getArg(args, namedArgs, 0, "editor", plugin_api.TextEditor), getArg(args, namedArgs, 1, "selections", seq[plugin_api.Selection]), getArg(args, namedArgs, 2, "contents", seq[string]), getArg(args, namedArgs, 3, "inclusive", bool), )
  return res.toJson().jsonTo(LispVal)
proc textEditorDefineMove*(instance: ptr InstanceData, args: LispVal, namedArgs: LispVal): LispVal =
  instance.textEditorDefineMove(getArg(args, namedArgs, 0, "move", string), getArg(args, namedArgs, 1, "fun", uint32), getArg(args, namedArgs, 2, "data", uint32), )
  return newNil()
proc vfsReadSync*(instance: ptr InstanceData, args: LispVal, namedArgs: LispVal): LispVal =
  let res = instance.vfsReadSync(getArg(args, namedArgs, 0, "path", string), getArg(args, namedArgs, 1, "read-flags", plugin_api.ReadFlags), )
  return res.toJson().jsonTo(LispVal)
proc vfsWriteSync*(instance: ptr InstanceData, args: LispVal, namedArgs: LispVal): LispVal =
  let res = instance.vfsWriteSync(getArg(args, namedArgs, 0, "path", string), getArg(args, namedArgs, 1, "content", string), )
  return res.toJson().jsonTo(LispVal)
proc vfsLocalize*(instance: ptr InstanceData, args: LispVal, namedArgs: LispVal): LispVal =
  let res = instance.vfsLocalize(getArg(args, namedArgs, 0, "path", string), )
  return res.toJson().jsonTo(LispVal)
proc registersIsReplayingCommands*(instance: ptr InstanceData, args: LispVal, namedArgs: LispVal): LispVal =
  let res = instance.registersIsReplayingCommands()
  return res.toJson().jsonTo(LispVal)
proc registersIsRecordingCommands*(instance: ptr InstanceData, args: LispVal, namedArgs: LispVal): LispVal =
  let res = instance.registersIsRecordingCommands(getArg(args, namedArgs, 0, "register", string), )
  return res.toJson().jsonTo(LispVal)
proc registersSetRegisterText*(instance: ptr InstanceData, args: LispVal, namedArgs: LispVal): LispVal =
  instance.registersSetRegisterText(getArg(args, namedArgs, 0, "text", string), getArg(args, namedArgs, 1, "register", string), )
  return newNil()
proc registersGetRegisterText*(instance: ptr InstanceData, args: LispVal, namedArgs: LispVal): LispVal =
  let res = instance.registersGetRegisterText(getArg(args, namedArgs, 0, "register", string), )
  return res.toJson().jsonTo(LispVal)
proc registersStartRecordingCommands*(instance: ptr InstanceData, args: LispVal, namedArgs: LispVal): LispVal =
  instance.registersStartRecordingCommands(getArg(args, namedArgs, 0, "register", string), )
  return newNil()
proc registersStopRecordingCommands*(instance: ptr InstanceData, args: LispVal, namedArgs: LispVal): LispVal =
  instance.registersStopRecordingCommands(getArg(args, namedArgs, 0, "register", string), )
  return newNil()
proc registersReplayCommands*(instance: ptr InstanceData, args: LispVal, namedArgs: LispVal): LispVal =
  instance.registersReplayCommands(getArg(args, namedArgs, 0, "register", string), )
  return newNil()
proc dispatchDynamic*(instance: ptr InstanceData, name: string, args: LispVal, namedArgs: LispVal): LispVal =
  case name
  of "core.api-version": coreApiVersion(instance, args, namedArgs)
  of "core.get-time": coreGetTime(instance, args, namedArgs)
  of "core.get-platform": coreGetPlatform(instance, args, namedArgs)
  of "core.is-main-thread": coreIsMainThread(instance, args, namedArgs)
  of "core.get-arguments": coreGetArguments(instance, args, namedArgs)
  of "core.spawn-background": coreSpawnBackground(instance, args, namedArgs)
  of "core.finish-background": coreFinishBackground(instance, args, namedArgs)
  of "commands.define-command": commandsDefineCommand(instance, args, namedArgs)
  of "commands.run-command": commandsRunCommand(instance, args, namedArgs)
  of "commands.exit-command-line": commandsExitCommandLine(instance, args, namedArgs)
  of "settings.get-setting-raw": settingsGetSettingRaw(instance, args, namedArgs)
  of "settings.set-setting-raw": settingsSetSettingRaw(instance, args, namedArgs)
  of "editor.active-editor": editorActiveEditor(instance, args, namedArgs)
  of "editor.get-document": editorGetDocument(instance, args, namedArgs)
  of "text-editor.active-text-editor": textEditorActiveTextEditor(instance, args, namedArgs)
  of "text-editor.get-document": textEditorGetDocument(instance, args, namedArgs)
  of "text-editor.as-text-editor": textEditorAsTextEditor(instance, args, namedArgs)
  of "text-editor.as-text-document": textEditorAsTextDocument(instance, args, namedArgs)
  of "text-editor.command": textEditorCommand(instance, args, namedArgs)
  of "text-editor.record-current-command": textEditorRecordCurrentCommand(instance, args, namedArgs)
  of "text-editor.hide-completions": textEditorHideCompletions(instance, args, namedArgs)
  of "text-editor.scroll-to-cursor": textEditorScrollToCursor(instance, args, namedArgs)
  of "text-editor.set-next-snap-behaviour": textEditorSetNextSnapBehaviour(instance, args, namedArgs)
  of "text-editor.update-target-column": textEditorUpdateTargetColumn(instance, args, namedArgs)
  of "text-editor.get-usage": textEditorGetUsage(instance, args, namedArgs)
  of "text-editor.get-revision": textEditorGetRevision(instance, args, namedArgs)
  of "text-editor.set-mode": textEditorSetMode(instance, args, namedArgs)
  of "text-editor.mode": textEditorMode(instance, args, namedArgs)
  of "text-editor.modes": textEditorModes(instance, args, namedArgs)
  of "text-editor.clear-tab-stops": textEditorClearTabStops(instance, args, namedArgs)
  of "text-editor.undo": textEditorUndo(instance, args, namedArgs)
  of "text-editor.redo": textEditorRedo(instance, args, namedArgs)
  of "text-editor.add-next-checkpoint": textEditorAddNextCheckpoint(instance, args, namedArgs)
  of "text-editor.copy": textEditorCopy(instance, args, namedArgs)
  of "text-editor.paste": textEditorPaste(instance, args, namedArgs)
  of "text-editor.auto-show-completions": textEditorAutoShowCompletions(instance, args, namedArgs)
  of "text-editor.toggle-line-comment": textEditorToggleLineComment(instance, args, namedArgs)
  of "text-editor.insert-text": textEditorInsertText(instance, args, namedArgs)
  of "text-editor.open-search-bar": textEditorOpenSearchBar(instance, args, namedArgs)
  of "text-editor.set-search-query-from-move": textEditorSetSearchQueryFromMove(instance, args, namedArgs)
  of "text-editor.set-search-query": textEditorSetSearchQuery(instance, args, namedArgs)
  of "text-editor.get-search-query": textEditorGetSearchQuery(instance, args, namedArgs)
  of "text-editor.apply-move": textEditorApplyMove(instance, args, namedArgs)
  of "text-editor.multi-move": textEditorMultiMove(instance, args, namedArgs)
  of "text-editor.set-selection": textEditorSetSelection(instance, args, namedArgs)
  of "text-editor.set-selections": textEditorSetSelections(instance, args, namedArgs)
  of "text-editor.get-selection": textEditorGetSelection(instance, args, namedArgs)
  of "text-editor.get-selections": textEditorGetSelections(instance, args, namedArgs)
  of "text-editor.line-length": textEditorLineLength(instance, args, namedArgs)
  of "text-editor.add-mode-changed-handler": textEditorAddModeChangedHandler(instance, args, namedArgs)
  of "text-editor.get-setting-raw": textEditorGetSettingRaw(instance, args, namedArgs)
  of "text-editor.set-setting-raw": textEditorSetSettingRaw(instance, args, namedArgs)
  of "text-editor.evaluate-expressions": textEditorEvaluateExpressions(instance, args, namedArgs)
  of "text-editor.indent": textEditorIndent(instance, args, namedArgs)
  of "text-editor.get-command-count": textEditorGetCommandCount(instance, args, namedArgs)
  of "text-editor.set-cursor-scroll-offset": textEditorSetCursorScrollOffset(instance, args, namedArgs)
  of "text-editor.get-visible-line-count": textEditorGetVisibleLineCount(instance, args, namedArgs)
  of "text-editor.create-anchors": textEditorCreateAnchors(instance, args, namedArgs)
  of "text-editor.resolve-anchors": textEditorResolveAnchors(instance, args, namedArgs)
  of "text-editor.edit": textEditorEdit(instance, args, namedArgs)
  of "text-editor.define-move": textEditorDefineMove(instance, args, namedArgs)
  of "vfs.read-sync": vfsReadSync(instance, args, namedArgs)
  of "vfs.write-sync": vfsWriteSync(instance, args, namedArgs)
  of "vfs.localize": vfsLocalize(instance, args, namedArgs)
  of "registers.is-replaying-commands": registersIsReplayingCommands(instance, args, namedArgs)
  of "registers.is-recording-commands": registersIsRecordingCommands(instance, args, namedArgs)
  of "registers.set-register-text": registersSetRegisterText(instance, args, namedArgs)
  of "registers.get-register-text": registersGetRegisterText(instance, args, namedArgs)
  of "registers.start-recording-commands": registersStartRecordingCommands(instance, args, namedArgs)
  of "registers.stop-recording-commands": registersStopRecordingCommands(instance, args, namedArgs)
  of "registers.replay-commands": registersReplayCommands(instance, args, namedArgs)
  else: echo("Unknown API '", name, "'"); newNil()
