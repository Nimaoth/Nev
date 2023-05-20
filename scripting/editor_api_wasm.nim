import std/[json, jsonutils]
import "../src/scripting_api"

## This file is auto generated, don't modify.


proc editor_getBackend_Backend_Editor_wasm(arg_2197823689: cstring): cstring {.
    importc.}
proc getBackend*(): Backend =
  var argsJson_2197823684 = newJArray()
  let argsJsonString = $argsJson_2197823684
  let res_2197823685 {.used.} = editor_getBackend_Backend_Editor_wasm(
      argsJsonString.cstring)
  result = parseJson($res_2197823685).jsonTo(typeof(result))


proc editor_saveAppState_void_Editor_wasm(arg_2197823859: cstring): cstring {.
    importc.}
proc saveAppState*() =
  var argsJson_2197823854 = newJArray()
  let argsJsonString = $argsJson_2197823854
  let res_2197823855 {.used.} = editor_saveAppState_void_Editor_wasm(
      argsJsonString.cstring)


proc editor_requestRender_void_Editor_bool_wasm(arg_2197824710: cstring): cstring {.
    importc.}
proc requestRender*(redrawEverything: bool = false) =
  var argsJson_2197824705 = newJArray()
  argsJson_2197824705.add block:
    when bool is JsonNode:
      redrawEverything
    else:
      redrawEverything.toJson()
  let argsJsonString = $argsJson_2197824705
  let res_2197824706 {.used.} = editor_requestRender_void_Editor_bool_wasm(
      argsJsonString.cstring)


proc editor_setHandleInputs_void_Editor_string_bool_wasm(arg_2197824766: cstring): cstring {.
    importc.}
proc setHandleInputs*(context: string; value: bool) =
  var argsJson_2197824761 = newJArray()
  argsJson_2197824761.add block:
    when string is JsonNode:
      context
    else:
      context.toJson()
  argsJson_2197824761.add block:
    when bool is JsonNode:
      value
    else:
      value.toJson()
  let argsJsonString = $argsJson_2197824761
  let res_2197824762 {.used.} = editor_setHandleInputs_void_Editor_string_bool_wasm(
      argsJsonString.cstring)


proc editor_setHandleActions_void_Editor_string_bool_wasm(arg_2197824830: cstring): cstring {.
    importc.}
proc setHandleActions*(context: string; value: bool) =
  var argsJson_2197824825 = newJArray()
  argsJson_2197824825.add block:
    when string is JsonNode:
      context
    else:
      context.toJson()
  argsJson_2197824825.add block:
    when bool is JsonNode:
      value
    else:
      value.toJson()
  let argsJsonString = $argsJson_2197824825
  let res_2197824826 {.used.} = editor_setHandleActions_void_Editor_string_bool_wasm(
      argsJsonString.cstring)


proc editor_setConsumeAllActions_void_Editor_string_bool_wasm(arg_2197824894: cstring): cstring {.
    importc.}
proc setConsumeAllActions*(context: string; value: bool) =
  var argsJson_2197824889 = newJArray()
  argsJson_2197824889.add block:
    when string is JsonNode:
      context
    else:
      context.toJson()
  argsJson_2197824889.add block:
    when bool is JsonNode:
      value
    else:
      value.toJson()
  let argsJsonString = $argsJson_2197824889
  let res_2197824890 {.used.} = editor_setConsumeAllActions_void_Editor_string_bool_wasm(
      argsJsonString.cstring)


proc editor_setConsumeAllInput_void_Editor_string_bool_wasm(arg_2197824958: cstring): cstring {.
    importc.}
proc setConsumeAllInput*(context: string; value: bool) =
  var argsJson_2197824953 = newJArray()
  argsJson_2197824953.add block:
    when string is JsonNode:
      context
    else:
      context.toJson()
  argsJson_2197824953.add block:
    when bool is JsonNode:
      value
    else:
      value.toJson()
  let argsJsonString = $argsJson_2197824953
  let res_2197824954 {.used.} = editor_setConsumeAllInput_void_Editor_string_bool_wasm(
      argsJsonString.cstring)


proc editor_clearWorkspaceCaches_void_Editor_wasm(arg_2197825099: cstring): cstring {.
    importc.}
proc clearWorkspaceCaches*() =
  var argsJson_2197825094 = newJArray()
  let argsJsonString = $argsJson_2197825094
  let res_2197825095 {.used.} = editor_clearWorkspaceCaches_void_Editor_wasm(
      argsJsonString.cstring)


proc editor_openGithubWorkspace_void_Editor_string_string_string_wasm(
    arg_2197825155: cstring): cstring {.importc.}
proc openGithubWorkspace*(user: string; repository: string; branchOrHash: string) =
  var argsJson_2197825150 = newJArray()
  argsJson_2197825150.add block:
    when string is JsonNode:
      user
    else:
      user.toJson()
  argsJson_2197825150.add block:
    when string is JsonNode:
      repository
    else:
      repository.toJson()
  argsJson_2197825150.add block:
    when string is JsonNode:
      branchOrHash
    else:
      branchOrHash.toJson()
  let argsJsonString = $argsJson_2197825150
  let res_2197825151 {.used.} = editor_openGithubWorkspace_void_Editor_string_string_string_wasm(
      argsJsonString.cstring)


proc editor_openAbsytreeServerWorkspace_void_Editor_string_wasm(arg_2197825231: cstring): cstring {.
    importc.}
proc openAbsytreeServerWorkspace*(url: string) =
  var argsJson_2197825226 = newJArray()
  argsJson_2197825226.add block:
    when string is JsonNode:
      url
    else:
      url.toJson()
  let argsJsonString = $argsJson_2197825226
  let res_2197825227 {.used.} = editor_openAbsytreeServerWorkspace_void_Editor_string_wasm(
      argsJsonString.cstring)


proc editor_openLocalWorkspace_void_Editor_string_wasm(arg_2197825287: cstring): cstring {.
    importc.}
proc openLocalWorkspace*(path: string) =
  var argsJson_2197825282 = newJArray()
  argsJson_2197825282.add block:
    when string is JsonNode:
      path
    else:
      path.toJson()
  let argsJsonString = $argsJson_2197825282
  let res_2197825283 {.used.} = editor_openLocalWorkspace_void_Editor_string_wasm(
      argsJsonString.cstring)


proc editor_getFlag_bool_Editor_string_bool_wasm(arg_2197825344: cstring): cstring {.
    importc.}
proc getFlag*(flag: string; default: bool = false): bool =
  var argsJson_2197825339 = newJArray()
  argsJson_2197825339.add block:
    when string is JsonNode:
      flag
    else:
      flag.toJson()
  argsJson_2197825339.add block:
    when bool is JsonNode:
      default
    else:
      default.toJson()
  let argsJsonString = $argsJson_2197825339
  let res_2197825340 {.used.} = editor_getFlag_bool_Editor_string_bool_wasm(
      argsJsonString.cstring)
  result = parseJson($res_2197825340).jsonTo(typeof(result))


proc editor_setFlag_void_Editor_string_bool_wasm(arg_2197825423: cstring): cstring {.
    importc.}
proc setFlag*(flag: string; value: bool) =
  var argsJson_2197825418 = newJArray()
  argsJson_2197825418.add block:
    when string is JsonNode:
      flag
    else:
      flag.toJson()
  argsJson_2197825418.add block:
    when bool is JsonNode:
      value
    else:
      value.toJson()
  let argsJsonString = $argsJson_2197825418
  let res_2197825419 {.used.} = editor_setFlag_void_Editor_string_bool_wasm(
      argsJsonString.cstring)


proc editor_toggleFlag_void_Editor_string_wasm(arg_2197825548: cstring): cstring {.
    importc.}
proc toggleFlag*(flag: string) =
  var argsJson_2197825543 = newJArray()
  argsJson_2197825543.add block:
    when string is JsonNode:
      flag
    else:
      flag.toJson()
  let argsJsonString = $argsJson_2197825543
  let res_2197825544 {.used.} = editor_toggleFlag_void_Editor_string_wasm(
      argsJsonString.cstring)


proc editor_setOption_void_Editor_string_JsonNode_wasm(arg_2197825604: cstring): cstring {.
    importc.}
proc setOption*(option: string; value: JsonNode) =
  var argsJson_2197825599 = newJArray()
  argsJson_2197825599.add block:
    when string is JsonNode:
      option
    else:
      option.toJson()
  argsJson_2197825599.add block:
    when JsonNode is JsonNode:
      value
    else:
      value.toJson()
  let argsJsonString = $argsJson_2197825599
  let res_2197825600 {.used.} = editor_setOption_void_Editor_string_JsonNode_wasm(
      argsJsonString.cstring)


proc editor_quit_void_Editor_wasm(arg_2197825707: cstring): cstring {.importc.}
proc quit*() =
  var argsJson_2197825702 = newJArray()
  let argsJsonString = $argsJson_2197825702
  let res_2197825703 {.used.} = editor_quit_void_Editor_wasm(
      argsJsonString.cstring)


proc editor_changeFontSize_void_Editor_float32_wasm(arg_2197825755: cstring): cstring {.
    importc.}
proc changeFontSize*(amount: float32) =
  var argsJson_2197825750 = newJArray()
  argsJson_2197825750.add block:
    when float32 is JsonNode:
      amount
    else:
      amount.toJson()
  let argsJsonString = $argsJson_2197825750
  let res_2197825751 {.used.} = editor_changeFontSize_void_Editor_float32_wasm(
      argsJsonString.cstring)


proc editor_changeLayoutProp_void_Editor_string_float32_wasm(arg_2197825811: cstring): cstring {.
    importc.}
proc changeLayoutProp*(prop: string; change: float32) =
  var argsJson_2197825806 = newJArray()
  argsJson_2197825806.add block:
    when string is JsonNode:
      prop
    else:
      prop.toJson()
  argsJson_2197825806.add block:
    when float32 is JsonNode:
      change
    else:
      change.toJson()
  let argsJsonString = $argsJson_2197825806
  let res_2197825807 {.used.} = editor_changeLayoutProp_void_Editor_string_float32_wasm(
      argsJsonString.cstring)


proc editor_toggleStatusBarLocation_void_Editor_wasm(arg_2197826142: cstring): cstring {.
    importc.}
proc toggleStatusBarLocation*() =
  var argsJson_2197826137 = newJArray()
  let argsJsonString = $argsJson_2197826137
  let res_2197826138 {.used.} = editor_toggleStatusBarLocation_void_Editor_wasm(
      argsJsonString.cstring)


proc editor_createView_void_Editor_wasm(arg_2197826190: cstring): cstring {.
    importc.}
proc createView*() =
  var argsJson_2197826185 = newJArray()
  let argsJsonString = $argsJson_2197826185
  let res_2197826186 {.used.} = editor_createView_void_Editor_wasm(
      argsJsonString.cstring)


proc editor_closeCurrentView_void_Editor_wasm(arg_2197826271: cstring): cstring {.
    importc.}
proc closeCurrentView*() =
  var argsJson_2197826266 = newJArray()
  let argsJsonString = $argsJson_2197826266
  let res_2197826267 {.used.} = editor_closeCurrentView_void_Editor_wasm(
      argsJsonString.cstring)


proc editor_moveCurrentViewToTop_void_Editor_wasm(arg_2197826364: cstring): cstring {.
    importc.}
proc moveCurrentViewToTop*() =
  var argsJson_2197826359 = newJArray()
  let argsJsonString = $argsJson_2197826359
  let res_2197826360 {.used.} = editor_moveCurrentViewToTop_void_Editor_wasm(
      argsJsonString.cstring)


proc editor_nextView_void_Editor_wasm(arg_2197826463: cstring): cstring {.
    importc.}
proc nextView*() =
  var argsJson_2197826458 = newJArray()
  let argsJsonString = $argsJson_2197826458
  let res_2197826459 {.used.} = editor_nextView_void_Editor_wasm(
      argsJsonString.cstring)


proc editor_prevView_void_Editor_wasm(arg_2197826517: cstring): cstring {.
    importc.}
proc prevView*() =
  var argsJson_2197826512 = newJArray()
  let argsJsonString = $argsJson_2197826512
  let res_2197826513 {.used.} = editor_prevView_void_Editor_wasm(
      argsJsonString.cstring)


proc editor_moveCurrentViewPrev_void_Editor_wasm(arg_2197826574: cstring): cstring {.
    importc.}
proc moveCurrentViewPrev*() =
  var argsJson_2197826569 = newJArray()
  let argsJsonString = $argsJson_2197826569
  let res_2197826570 {.used.} = editor_moveCurrentViewPrev_void_Editor_wasm(
      argsJsonString.cstring)


proc editor_moveCurrentViewNext_void_Editor_wasm(arg_2197826645: cstring): cstring {.
    importc.}
proc moveCurrentViewNext*() =
  var argsJson_2197826640 = newJArray()
  let argsJsonString = $argsJson_2197826640
  let res_2197826641 {.used.} = editor_moveCurrentViewNext_void_Editor_wasm(
      argsJsonString.cstring)


proc editor_setLayout_void_Editor_string_wasm(arg_2197826713: cstring): cstring {.
    importc.}
proc setLayout*(layout: string) =
  var argsJson_2197826708 = newJArray()
  argsJson_2197826708.add block:
    when string is JsonNode:
      layout
    else:
      layout.toJson()
  let argsJsonString = $argsJson_2197826708
  let res_2197826709 {.used.} = editor_setLayout_void_Editor_string_wasm(
      argsJsonString.cstring)


proc editor_commandLine_void_Editor_string_wasm(arg_2197826805: cstring): cstring {.
    importc.}
proc commandLine*(initialValue: string = "") =
  var argsJson_2197826800 = newJArray()
  argsJson_2197826800.add block:
    when string is JsonNode:
      initialValue
    else:
      initialValue.toJson()
  let argsJsonString = $argsJson_2197826800
  let res_2197826801 {.used.} = editor_commandLine_void_Editor_string_wasm(
      argsJsonString.cstring)


proc editor_exitCommandLine_void_Editor_wasm(arg_2197826865: cstring): cstring {.
    importc.}
proc exitCommandLine*() =
  var argsJson_2197826860 = newJArray()
  let argsJsonString = $argsJson_2197826860
  let res_2197826861 {.used.} = editor_exitCommandLine_void_Editor_wasm(
      argsJsonString.cstring)


proc editor_executeCommandLine_bool_Editor_wasm(arg_2197826917: cstring): cstring {.
    importc.}
proc executeCommandLine*(): bool =
  var argsJson_2197826912 = newJArray()
  let argsJsonString = $argsJson_2197826912
  let res_2197826913 {.used.} = editor_executeCommandLine_bool_Editor_wasm(
      argsJsonString.cstring)
  result = parseJson($res_2197826913).jsonTo(typeof(result))


proc editor_writeFile_void_Editor_string_bool_wasm(arg_2197827098: cstring): cstring {.
    importc.}
proc writeFile*(path: string = ""; app: bool = false) =
  var argsJson_2197827093 = newJArray()
  argsJson_2197827093.add block:
    when string is JsonNode:
      path
    else:
      path.toJson()
  argsJson_2197827093.add block:
    when bool is JsonNode:
      app
    else:
      app.toJson()
  let argsJsonString = $argsJson_2197827093
  let res_2197827094 {.used.} = editor_writeFile_void_Editor_string_bool_wasm(
      argsJsonString.cstring)


proc editor_loadFile_void_Editor_string_wasm(arg_2197827174: cstring): cstring {.
    importc.}
proc loadFile*(path: string = "") =
  var argsJson_2197827169 = newJArray()
  argsJson_2197827169.add block:
    when string is JsonNode:
      path
    else:
      path.toJson()
  let argsJsonString = $argsJson_2197827169
  let res_2197827170 {.used.} = editor_loadFile_void_Editor_string_wasm(
      argsJsonString.cstring)


proc editor_openFile_void_Editor_string_bool_wasm(arg_2197827261: cstring): cstring {.
    importc.}
proc openFile*(path: string; app: bool = false) =
  var argsJson_2197827256 = newJArray()
  argsJson_2197827256.add block:
    when string is JsonNode:
      path
    else:
      path.toJson()
  argsJson_2197827256.add block:
    when bool is JsonNode:
      app
    else:
      app.toJson()
  let argsJsonString = $argsJson_2197827256
  let res_2197827257 {.used.} = editor_openFile_void_Editor_string_bool_wasm(
      argsJsonString.cstring)


proc editor_removeFromLocalStorage_void_Editor_wasm(arg_2197827444: cstring): cstring {.
    importc.}
proc removeFromLocalStorage*() =
  var argsJson_2197827439 = newJArray()
  let argsJsonString = $argsJson_2197827439
  let res_2197827440 {.used.} = editor_removeFromLocalStorage_void_Editor_wasm(
      argsJsonString.cstring)


proc editor_loadTheme_void_Editor_string_wasm(arg_2197827492: cstring): cstring {.
    importc.}
proc loadTheme*(name: string) =
  var argsJson_2197827487 = newJArray()
  argsJson_2197827487.add block:
    when string is JsonNode:
      name
    else:
      name.toJson()
  let argsJsonString = $argsJson_2197827487
  let res_2197827488 {.used.} = editor_loadTheme_void_Editor_string_wasm(
      argsJsonString.cstring)


proc editor_chooseTheme_void_Editor_wasm(arg_2197827584: cstring): cstring {.
    importc.}
proc chooseTheme*() =
  var argsJson_2197827579 = newJArray()
  let argsJsonString = $argsJson_2197827579
  let res_2197827580 {.used.} = editor_chooseTheme_void_Editor_wasm(
      argsJsonString.cstring)


proc editor_chooseFile_void_Editor_string_wasm(arg_2197828281: cstring): cstring {.
    importc.}
proc chooseFile*(view: string = "new") =
  var argsJson_2197828276 = newJArray()
  argsJson_2197828276.add block:
    when string is JsonNode:
      view
    else:
      view.toJson()
  let argsJsonString = $argsJson_2197828276
  let res_2197828277 {.used.} = editor_chooseFile_void_Editor_string_wasm(
      argsJsonString.cstring)


proc editor_setGithubAccessToken_void_Editor_string_wasm(arg_2197828843: cstring): cstring {.
    importc.}
proc setGithubAccessToken*(token: string) =
  var argsJson_2197828838 = newJArray()
  argsJson_2197828838.add block:
    when string is JsonNode:
      token
    else:
      token.toJson()
  let argsJsonString = $argsJson_2197828838
  let res_2197828839 {.used.} = editor_setGithubAccessToken_void_Editor_string_wasm(
      argsJsonString.cstring)


proc editor_reloadConfig_void_Editor_wasm(arg_2197828899: cstring): cstring {.
    importc.}
proc reloadConfig*() =
  var argsJson_2197828894 = newJArray()
  let argsJsonString = $argsJson_2197828894
  let res_2197828895 {.used.} = editor_reloadConfig_void_Editor_wasm(
      argsJsonString.cstring)


proc editor_logOptions_void_Editor_wasm(arg_2197828989: cstring): cstring {.
    importc.}
proc logOptions*() =
  var argsJson_2197828984 = newJArray()
  let argsJsonString = $argsJson_2197828984
  let res_2197828985 {.used.} = editor_logOptions_void_Editor_wasm(
      argsJsonString.cstring)


proc editor_clearCommands_void_Editor_string_wasm(arg_2197829037: cstring): cstring {.
    importc.}
proc clearCommands*(context: string) =
  var argsJson_2197829032 = newJArray()
  argsJson_2197829032.add block:
    when string is JsonNode:
      context
    else:
      context.toJson()
  let argsJsonString = $argsJson_2197829032
  let res_2197829033 {.used.} = editor_clearCommands_void_Editor_string_wasm(
      argsJsonString.cstring)


proc editor_getAllEditors_seq_EditorId_Editor_wasm(arg_2197829093: cstring): cstring {.
    importc.}
proc getAllEditors*(): seq[EditorId] =
  var argsJson_2197829088 = newJArray()
  let argsJsonString = $argsJson_2197829088
  let res_2197829089 {.used.} = editor_getAllEditors_seq_EditorId_Editor_wasm(
      argsJsonString.cstring)
  result = parseJson($res_2197829089).jsonTo(typeof(result))


proc editor_setMode_void_Editor_string_wasm(arg_2197829417: cstring): cstring {.
    importc.}
proc setMode*(mode: string) =
  var argsJson_2197829412 = newJArray()
  argsJson_2197829412.add block:
    when string is JsonNode:
      mode
    else:
      mode.toJson()
  let argsJsonString = $argsJson_2197829412
  let res_2197829413 {.used.} = editor_setMode_void_Editor_string_wasm(
      argsJsonString.cstring)


proc editor_mode_string_Editor_wasm(arg_2197829531: cstring): cstring {.importc.}
proc mode*(): string =
  var argsJson_2197829526 = newJArray()
  let argsJsonString = $argsJson_2197829526
  let res_2197829527 {.used.} = editor_mode_string_Editor_wasm(
      argsJsonString.cstring)
  result = parseJson($res_2197829527).jsonTo(typeof(result))


proc editor_getContextWithMode_string_Editor_string_wasm(arg_2197829585: cstring): cstring {.
    importc.}
proc getContextWithMode*(context: string): string =
  var argsJson_2197829580 = newJArray()
  argsJson_2197829580.add block:
    when string is JsonNode:
      context
    else:
      context.toJson()
  let argsJsonString = $argsJson_2197829580
  let res_2197829581 {.used.} = editor_getContextWithMode_string_Editor_string_wasm(
      argsJsonString.cstring)
  result = parseJson($res_2197829581).jsonTo(typeof(result))


proc editor_scriptRunAction_void_string_string_wasm(arg_2197829873: cstring): cstring {.
    importc.}
proc scriptRunAction*(action: string; arg: string) =
  var argsJson_2197829869 = newJArray()
  argsJson_2197829869.add block:
    when string is JsonNode:
      action
    else:
      action.toJson()
  argsJson_2197829869.add block:
    when string is JsonNode:
      arg
    else:
      arg.toJson()
  let argsJsonString = $argsJson_2197829869
  let res_2197829870 {.used.} = editor_scriptRunAction_void_string_string_wasm(
      argsJsonString.cstring)


proc editor_scriptLog_void_string_wasm(arg_2197829914: cstring): cstring {.
    importc.}
proc scriptLog*(message: string) =
  var argsJson_2197829910 = newJArray()
  argsJson_2197829910.add block:
    when string is JsonNode:
      message
    else:
      message.toJson()
  let argsJsonString = $argsJson_2197829910
  let res_2197829911 {.used.} = editor_scriptLog_void_string_wasm(
      argsJsonString.cstring)


proc editor_addCommandScript_void_Editor_string_string_string_string_wasm(
    arg_2197829950: cstring): cstring {.importc.}
proc addCommandScript*(context: string; keys: string; action: string;
                       arg: string = "") =
  var argsJson_2197829945 = newJArray()
  argsJson_2197829945.add block:
    when string is JsonNode:
      context
    else:
      context.toJson()
  argsJson_2197829945.add block:
    when string is JsonNode:
      keys
    else:
      keys.toJson()
  argsJson_2197829945.add block:
    when string is JsonNode:
      action
    else:
      action.toJson()
  argsJson_2197829945.add block:
    when string is JsonNode:
      arg
    else:
      arg.toJson()
  let argsJsonString = $argsJson_2197829945
  let res_2197829946 {.used.} = editor_addCommandScript_void_Editor_string_string_string_string_wasm(
      argsJsonString.cstring)


proc editor_removeCommand_void_Editor_string_string_wasm(arg_2197830031: cstring): cstring {.
    importc.}
proc removeCommand*(context: string; keys: string) =
  var argsJson_2197830026 = newJArray()
  argsJson_2197830026.add block:
    when string is JsonNode:
      context
    else:
      context.toJson()
  argsJson_2197830026.add block:
    when string is JsonNode:
      keys
    else:
      keys.toJson()
  let argsJsonString = $argsJson_2197830026
  let res_2197830027 {.used.} = editor_removeCommand_void_Editor_string_string_wasm(
      argsJsonString.cstring)


proc editor_getActivePopup_EditorId_wasm(arg_2197830094: cstring): cstring {.
    importc.}
proc getActivePopup*(): EditorId =
  var argsJson_2197830090 = newJArray()
  let argsJsonString = $argsJson_2197830090
  let res_2197830091 {.used.} = editor_getActivePopup_EditorId_wasm(
      argsJsonString.cstring)
  result = parseJson($res_2197830091).jsonTo(typeof(result))


proc editor_getActiveEditor_EditorId_wasm(arg_2197830134: cstring): cstring {.
    importc.}
proc getActiveEditor*(): EditorId =
  var argsJson_2197830130 = newJArray()
  let argsJsonString = $argsJson_2197830130
  let res_2197830131 {.used.} = editor_getActiveEditor_EditorId_wasm(
      argsJsonString.cstring)
  result = parseJson($res_2197830131).jsonTo(typeof(result))


proc editor_getActiveEditor2_EditorId_Editor_wasm(arg_2197830169: cstring): cstring {.
    importc.}
proc getActiveEditor2*(): EditorId =
  var argsJson_2197830164 = newJArray()
  let argsJsonString = $argsJson_2197830164
  let res_2197830165 {.used.} = editor_getActiveEditor2_EditorId_Editor_wasm(
      argsJsonString.cstring)
  result = parseJson($res_2197830165).jsonTo(typeof(result))


proc editor_loadCurrentConfig_void_Editor_wasm(arg_2197830223: cstring): cstring {.
    importc.}
proc loadCurrentConfig*() =
  var argsJson_2197830218 = newJArray()
  let argsJsonString = $argsJson_2197830218
  let res_2197830219 {.used.} = editor_loadCurrentConfig_void_Editor_wasm(
      argsJsonString.cstring)


proc editor_sourceCurrentDocument_void_Editor_wasm(arg_2197830271: cstring): cstring {.
    importc.}
proc sourceCurrentDocument*() =
  var argsJson_2197830266 = newJArray()
  let argsJsonString = $argsJson_2197830266
  let res_2197830267 {.used.} = editor_sourceCurrentDocument_void_Editor_wasm(
      argsJsonString.cstring)


proc editor_getEditor_EditorId_int_wasm(arg_2197830318: cstring): cstring {.
    importc.}
proc getEditor*(index: int): EditorId =
  var argsJson_2197830314 = newJArray()
  argsJson_2197830314.add block:
    when int is JsonNode:
      index
    else:
      index.toJson()
  let argsJsonString = $argsJson_2197830314
  let res_2197830315 {.used.} = editor_getEditor_EditorId_int_wasm(
      argsJsonString.cstring)
  result = parseJson($res_2197830315).jsonTo(typeof(result))


proc editor_scriptIsTextEditor_bool_EditorId_wasm(arg_2197830360: cstring): cstring {.
    importc.}
proc scriptIsTextEditor*(editorId: EditorId): bool =
  var argsJson_2197830356 = newJArray()
  argsJson_2197830356.add block:
    when EditorId is JsonNode:
      editorId
    else:
      editorId.toJson()
  let argsJsonString = $argsJson_2197830356
  let res_2197830357 {.used.} = editor_scriptIsTextEditor_bool_EditorId_wasm(
      argsJsonString.cstring)
  result = parseJson($res_2197830357).jsonTo(typeof(result))


proc editor_scriptIsAstEditor_bool_EditorId_wasm(arg_2197830431: cstring): cstring {.
    importc.}
proc scriptIsAstEditor*(editorId: EditorId): bool =
  var argsJson_2197830427 = newJArray()
  argsJson_2197830427.add block:
    when EditorId is JsonNode:
      editorId
    else:
      editorId.toJson()
  let argsJsonString = $argsJson_2197830427
  let res_2197830428 {.used.} = editor_scriptIsAstEditor_bool_EditorId_wasm(
      argsJsonString.cstring)
  result = parseJson($res_2197830428).jsonTo(typeof(result))


proc editor_scriptIsModelEditor_bool_EditorId_wasm(arg_2197830502: cstring): cstring {.
    importc.}
proc scriptIsModelEditor*(editorId: EditorId): bool =
  var argsJson_2197830498 = newJArray()
  argsJson_2197830498.add block:
    when EditorId is JsonNode:
      editorId
    else:
      editorId.toJson()
  let argsJsonString = $argsJson_2197830498
  let res_2197830499 {.used.} = editor_scriptIsModelEditor_bool_EditorId_wasm(
      argsJsonString.cstring)
  result = parseJson($res_2197830499).jsonTo(typeof(result))


proc editor_scriptRunActionFor_void_EditorId_string_string_wasm(arg_2197830573: cstring): cstring {.
    importc.}
proc scriptRunActionFor*(editorId: EditorId; action: string; arg: string) =
  var argsJson_2197830569 = newJArray()
  argsJson_2197830569.add block:
    when EditorId is JsonNode:
      editorId
    else:
      editorId.toJson()
  argsJson_2197830569.add block:
    when string is JsonNode:
      action
    else:
      action.toJson()
  argsJson_2197830569.add block:
    when string is JsonNode:
      arg
    else:
      arg.toJson()
  let argsJsonString = $argsJson_2197830569
  let res_2197830570 {.used.} = editor_scriptRunActionFor_void_EditorId_string_string_wasm(
      argsJsonString.cstring)


proc editor_scriptInsertTextInto_void_EditorId_string_wasm(arg_2197830678: cstring): cstring {.
    importc.}
proc scriptInsertTextInto*(editorId: EditorId; text: string) =
  var argsJson_2197830674 = newJArray()
  argsJson_2197830674.add block:
    when EditorId is JsonNode:
      editorId
    else:
      editorId.toJson()
  argsJson_2197830674.add block:
    when string is JsonNode:
      text
    else:
      text.toJson()
  let argsJsonString = $argsJson_2197830674
  let res_2197830675 {.used.} = editor_scriptInsertTextInto_void_EditorId_string_wasm(
      argsJsonString.cstring)


proc editor_scriptTextEditorSelection_Selection_EditorId_wasm(arg_2197830747: cstring): cstring {.
    importc.}
proc scriptTextEditorSelection*(editorId: EditorId): Selection =
  var argsJson_2197830743 = newJArray()
  argsJson_2197830743.add block:
    when EditorId is JsonNode:
      editorId
    else:
      editorId.toJson()
  let argsJsonString = $argsJson_2197830743
  let res_2197830744 {.used.} = editor_scriptTextEditorSelection_Selection_EditorId_wasm(
      argsJsonString.cstring)
  result = parseJson($res_2197830744).jsonTo(typeof(result))


proc editor_scriptSetTextEditorSelection_void_EditorId_Selection_wasm(
    arg_2197830823: cstring): cstring {.importc.}
proc scriptSetTextEditorSelection*(editorId: EditorId; selection: Selection) =
  var argsJson_2197830819 = newJArray()
  argsJson_2197830819.add block:
    when EditorId is JsonNode:
      editorId
    else:
      editorId.toJson()
  argsJson_2197830819.add block:
    when Selection is JsonNode:
      selection
    else:
      selection.toJson()
  let argsJsonString = $argsJson_2197830819
  let res_2197830820 {.used.} = editor_scriptSetTextEditorSelection_void_EditorId_Selection_wasm(
      argsJsonString.cstring)


proc editor_scriptTextEditorSelections_seq_Selection_EditorId_wasm(arg_2197830896: cstring): cstring {.
    importc.}
proc scriptTextEditorSelections*(editorId: EditorId): seq[Selection] =
  var argsJson_2197830892 = newJArray()
  argsJson_2197830892.add block:
    when EditorId is JsonNode:
      editorId
    else:
      editorId.toJson()
  let argsJsonString = $argsJson_2197830892
  let res_2197830893 {.used.} = editor_scriptTextEditorSelections_seq_Selection_EditorId_wasm(
      argsJsonString.cstring)
  result = parseJson($res_2197830893).jsonTo(typeof(result))


proc editor_scriptSetTextEditorSelections_void_EditorId_seq_Selection_wasm(
    arg_2197830976: cstring): cstring {.importc.}
proc scriptSetTextEditorSelections*(editorId: EditorId;
                                    selections: seq[Selection]) =
  var argsJson_2197830972 = newJArray()
  argsJson_2197830972.add block:
    when EditorId is JsonNode:
      editorId
    else:
      editorId.toJson()
  argsJson_2197830972.add block:
    when seq[Selection] is JsonNode:
      selections
    else:
      selections.toJson()
  let argsJsonString = $argsJson_2197830972
  let res_2197830973 {.used.} = editor_scriptSetTextEditorSelections_void_EditorId_seq_Selection_wasm(
      argsJsonString.cstring)


proc editor_scriptGetTextEditorLine_string_EditorId_int_wasm(arg_2197831049: cstring): cstring {.
    importc.}
proc scriptGetTextEditorLine*(editorId: EditorId; line: int): string =
  var argsJson_2197831045 = newJArray()
  argsJson_2197831045.add block:
    when EditorId is JsonNode:
      editorId
    else:
      editorId.toJson()
  argsJson_2197831045.add block:
    when int is JsonNode:
      line
    else:
      line.toJson()
  let argsJsonString = $argsJson_2197831045
  let res_2197831046 {.used.} = editor_scriptGetTextEditorLine_string_EditorId_int_wasm(
      argsJsonString.cstring)
  result = parseJson($res_2197831046).jsonTo(typeof(result))


proc editor_scriptGetTextEditorLineCount_int_EditorId_wasm(arg_2197831132: cstring): cstring {.
    importc.}
proc scriptGetTextEditorLineCount*(editorId: EditorId): int =
  var argsJson_2197831128 = newJArray()
  argsJson_2197831128.add block:
    when EditorId is JsonNode:
      editorId
    else:
      editorId.toJson()
  let argsJsonString = $argsJson_2197831128
  let res_2197831129 {.used.} = editor_scriptGetTextEditorLineCount_int_EditorId_wasm(
      argsJsonString.cstring)
  result = parseJson($res_2197831129).jsonTo(typeof(result))


proc editor_scriptGetOptionInt_int_string_int_wasm(arg_2197831218: cstring): cstring {.
    importc.}
proc scriptGetOptionInt*(path: string; default: int): int =
  var argsJson_2197831214 = newJArray()
  argsJson_2197831214.add block:
    when string is JsonNode:
      path
    else:
      path.toJson()
  argsJson_2197831214.add block:
    when int is JsonNode:
      default
    else:
      default.toJson()
  let argsJsonString = $argsJson_2197831214
  let res_2197831215 {.used.} = editor_scriptGetOptionInt_int_string_int_wasm(
      argsJsonString.cstring)
  result = parseJson($res_2197831215).jsonTo(typeof(result))


proc editor_scriptGetOptionFloat_float_string_float_wasm(arg_2197831271: cstring): cstring {.
    importc.}
proc scriptGetOptionFloat*(path: string; default: float): float =
  var argsJson_2197831267 = newJArray()
  argsJson_2197831267.add block:
    when string is JsonNode:
      path
    else:
      path.toJson()
  argsJson_2197831267.add block:
    when float is JsonNode:
      default
    else:
      default.toJson()
  let argsJsonString = $argsJson_2197831267
  let res_2197831268 {.used.} = editor_scriptGetOptionFloat_float_string_float_wasm(
      argsJsonString.cstring)
  result = parseJson($res_2197831268).jsonTo(typeof(result))


proc editor_scriptGetOptionBool_bool_string_bool_wasm(arg_2197831382: cstring): cstring {.
    importc.}
proc scriptGetOptionBool*(path: string; default: bool): bool =
  var argsJson_2197831378 = newJArray()
  argsJson_2197831378.add block:
    when string is JsonNode:
      path
    else:
      path.toJson()
  argsJson_2197831378.add block:
    when bool is JsonNode:
      default
    else:
      default.toJson()
  let argsJsonString = $argsJson_2197831378
  let res_2197831379 {.used.} = editor_scriptGetOptionBool_bool_string_bool_wasm(
      argsJsonString.cstring)
  result = parseJson($res_2197831379).jsonTo(typeof(result))


proc editor_scriptGetOptionString_string_string_string_wasm(arg_2197831435: cstring): cstring {.
    importc.}
proc scriptGetOptionString*(path: string; default: string): string =
  var argsJson_2197831431 = newJArray()
  argsJson_2197831431.add block:
    when string is JsonNode:
      path
    else:
      path.toJson()
  argsJson_2197831431.add block:
    when string is JsonNode:
      default
    else:
      default.toJson()
  let argsJsonString = $argsJson_2197831431
  let res_2197831432 {.used.} = editor_scriptGetOptionString_string_string_string_wasm(
      argsJsonString.cstring)
  result = parseJson($res_2197831432).jsonTo(typeof(result))


proc editor_scriptSetOptionInt_void_string_int_wasm(arg_2197831488: cstring): cstring {.
    importc.}
proc scriptSetOptionInt*(path: string; value: int) =
  var argsJson_2197831484 = newJArray()
  argsJson_2197831484.add block:
    when string is JsonNode:
      path
    else:
      path.toJson()
  argsJson_2197831484.add block:
    when int is JsonNode:
      value
    else:
      value.toJson()
  let argsJsonString = $argsJson_2197831484
  let res_2197831485 {.used.} = editor_scriptSetOptionInt_void_string_int_wasm(
      argsJsonString.cstring)


proc editor_scriptSetOptionFloat_void_string_float_wasm(arg_2197831574: cstring): cstring {.
    importc.}
proc scriptSetOptionFloat*(path: string; value: float) =
  var argsJson_2197831570 = newJArray()
  argsJson_2197831570.add block:
    when string is JsonNode:
      path
    else:
      path.toJson()
  argsJson_2197831570.add block:
    when float is JsonNode:
      value
    else:
      value.toJson()
  let argsJsonString = $argsJson_2197831570
  let res_2197831571 {.used.} = editor_scriptSetOptionFloat_void_string_float_wasm(
      argsJsonString.cstring)


proc editor_scriptSetOptionBool_void_string_bool_wasm(arg_2197831660: cstring): cstring {.
    importc.}
proc scriptSetOptionBool*(path: string; value: bool) =
  var argsJson_2197831656 = newJArray()
  argsJson_2197831656.add block:
    when string is JsonNode:
      path
    else:
      path.toJson()
  argsJson_2197831656.add block:
    when bool is JsonNode:
      value
    else:
      value.toJson()
  let argsJsonString = $argsJson_2197831656
  let res_2197831657 {.used.} = editor_scriptSetOptionBool_void_string_bool_wasm(
      argsJsonString.cstring)


proc editor_scriptSetOptionString_void_string_string_wasm(arg_2197831746: cstring): cstring {.
    importc.}
proc scriptSetOptionString*(path: string; value: string) =
  var argsJson_2197831742 = newJArray()
  argsJson_2197831742.add block:
    when string is JsonNode:
      path
    else:
      path.toJson()
  argsJson_2197831742.add block:
    when string is JsonNode:
      value
    else:
      value.toJson()
  let argsJsonString = $argsJson_2197831742
  let res_2197831743 {.used.} = editor_scriptSetOptionString_void_string_string_wasm(
      argsJsonString.cstring)


proc editor_scriptSetCallback_void_string_int_wasm(arg_2197831832: cstring): cstring {.
    importc.}
proc scriptSetCallback*(path: string; id: int) =
  var argsJson_2197831828 = newJArray()
  argsJson_2197831828.add block:
    when string is JsonNode:
      path
    else:
      path.toJson()
  argsJson_2197831828.add block:
    when int is JsonNode:
      id
    else:
      id.toJson()
  let argsJsonString = $argsJson_2197831828
  let res_2197831829 {.used.} = editor_scriptSetCallback_void_string_int_wasm(
      argsJsonString.cstring)

