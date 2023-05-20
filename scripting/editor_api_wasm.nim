import std/[json, jsonutils]
import "../src/scripting_api"

## This file is auto generated, don't modify.


proc editor_getBackend_Backend_Editor_wasm(arg_2197823690: cstring): cstring {.
    importc.}
proc getBackend*(): Backend =
  var argsJson_2197823685 = newJArray()
  let argsJsonString = $argsJson_2197823685
  let res_2197823686 {.used.} = editor_getBackend_Backend_Editor_wasm(
      argsJsonString.cstring)
  result = parseJson($res_2197823686).jsonTo(typeof(result))


proc editor_saveAppState_void_Editor_wasm(arg_2197823861: cstring): cstring {.
    importc.}
proc saveAppState*() =
  var argsJson_2197823856 = newJArray()
  let argsJsonString = $argsJson_2197823856
  let res_2197823857 {.used.} = editor_saveAppState_void_Editor_wasm(
      argsJsonString.cstring)


proc editor_requestRender_void_Editor_bool_wasm(arg_2197824713: cstring): cstring {.
    importc.}
proc requestRender*(redrawEverything: bool = false) =
  var argsJson_2197824708 = newJArray()
  argsJson_2197824708.add block:
    when bool is JsonNode:
      redrawEverything
    else:
      redrawEverything.toJson()
  let argsJsonString = $argsJson_2197824708
  let res_2197824709 {.used.} = editor_requestRender_void_Editor_bool_wasm(
      argsJsonString.cstring)


proc editor_setHandleInputs_void_Editor_string_bool_wasm(arg_2197824770: cstring): cstring {.
    importc.}
proc setHandleInputs*(context: string; value: bool) =
  var argsJson_2197824765 = newJArray()
  argsJson_2197824765.add block:
    when string is JsonNode:
      context
    else:
      context.toJson()
  argsJson_2197824765.add block:
    when bool is JsonNode:
      value
    else:
      value.toJson()
  let argsJsonString = $argsJson_2197824765
  let res_2197824766 {.used.} = editor_setHandleInputs_void_Editor_string_bool_wasm(
      argsJsonString.cstring)


proc editor_setHandleActions_void_Editor_string_bool_wasm(arg_2197824835: cstring): cstring {.
    importc.}
proc setHandleActions*(context: string; value: bool) =
  var argsJson_2197824830 = newJArray()
  argsJson_2197824830.add block:
    when string is JsonNode:
      context
    else:
      context.toJson()
  argsJson_2197824830.add block:
    when bool is JsonNode:
      value
    else:
      value.toJson()
  let argsJsonString = $argsJson_2197824830
  let res_2197824831 {.used.} = editor_setHandleActions_void_Editor_string_bool_wasm(
      argsJsonString.cstring)


proc editor_setConsumeAllActions_void_Editor_string_bool_wasm(arg_2197824900: cstring): cstring {.
    importc.}
proc setConsumeAllActions*(context: string; value: bool) =
  var argsJson_2197824895 = newJArray()
  argsJson_2197824895.add block:
    when string is JsonNode:
      context
    else:
      context.toJson()
  argsJson_2197824895.add block:
    when bool is JsonNode:
      value
    else:
      value.toJson()
  let argsJsonString = $argsJson_2197824895
  let res_2197824896 {.used.} = editor_setConsumeAllActions_void_Editor_string_bool_wasm(
      argsJsonString.cstring)


proc editor_setConsumeAllInput_void_Editor_string_bool_wasm(arg_2197824965: cstring): cstring {.
    importc.}
proc setConsumeAllInput*(context: string; value: bool) =
  var argsJson_2197824960 = newJArray()
  argsJson_2197824960.add block:
    when string is JsonNode:
      context
    else:
      context.toJson()
  argsJson_2197824960.add block:
    when bool is JsonNode:
      value
    else:
      value.toJson()
  let argsJsonString = $argsJson_2197824960
  let res_2197824961 {.used.} = editor_setConsumeAllInput_void_Editor_string_bool_wasm(
      argsJsonString.cstring)


proc editor_clearWorkspaceCaches_void_Editor_wasm(arg_2197825107: cstring): cstring {.
    importc.}
proc clearWorkspaceCaches*() =
  var argsJson_2197825102 = newJArray()
  let argsJsonString = $argsJson_2197825102
  let res_2197825103 {.used.} = editor_clearWorkspaceCaches_void_Editor_wasm(
      argsJsonString.cstring)


proc editor_openGithubWorkspace_void_Editor_string_string_string_wasm(
    arg_2197825164: cstring): cstring {.importc.}
proc openGithubWorkspace*(user: string; repository: string; branchOrHash: string) =
  var argsJson_2197825159 = newJArray()
  argsJson_2197825159.add block:
    when string is JsonNode:
      user
    else:
      user.toJson()
  argsJson_2197825159.add block:
    when string is JsonNode:
      repository
    else:
      repository.toJson()
  argsJson_2197825159.add block:
    when string is JsonNode:
      branchOrHash
    else:
      branchOrHash.toJson()
  let argsJsonString = $argsJson_2197825159
  let res_2197825160 {.used.} = editor_openGithubWorkspace_void_Editor_string_string_string_wasm(
      argsJsonString.cstring)


proc editor_openAbsytreeServerWorkspace_void_Editor_string_wasm(arg_2197825241: cstring): cstring {.
    importc.}
proc openAbsytreeServerWorkspace*(url: string) =
  var argsJson_2197825236 = newJArray()
  argsJson_2197825236.add block:
    when string is JsonNode:
      url
    else:
      url.toJson()
  let argsJsonString = $argsJson_2197825236
  let res_2197825237 {.used.} = editor_openAbsytreeServerWorkspace_void_Editor_string_wasm(
      argsJsonString.cstring)


proc editor_openLocalWorkspace_void_Editor_string_wasm(arg_2197825298: cstring): cstring {.
    importc.}
proc openLocalWorkspace*(path: string) =
  var argsJson_2197825293 = newJArray()
  argsJson_2197825293.add block:
    when string is JsonNode:
      path
    else:
      path.toJson()
  let argsJsonString = $argsJson_2197825293
  let res_2197825294 {.used.} = editor_openLocalWorkspace_void_Editor_string_wasm(
      argsJsonString.cstring)


proc editor_getFlag_bool_Editor_string_bool_wasm(arg_2197825356: cstring): cstring {.
    importc.}
proc getFlag*(flag: string; default: bool = false): bool =
  var argsJson_2197825351 = newJArray()
  argsJson_2197825351.add block:
    when string is JsonNode:
      flag
    else:
      flag.toJson()
  argsJson_2197825351.add block:
    when bool is JsonNode:
      default
    else:
      default.toJson()
  let argsJsonString = $argsJson_2197825351
  let res_2197825352 {.used.} = editor_getFlag_bool_Editor_string_bool_wasm(
      argsJsonString.cstring)
  result = parseJson($res_2197825352).jsonTo(typeof(result))


proc editor_setFlag_void_Editor_string_bool_wasm(arg_2197825436: cstring): cstring {.
    importc.}
proc setFlag*(flag: string; value: bool) =
  var argsJson_2197825431 = newJArray()
  argsJson_2197825431.add block:
    when string is JsonNode:
      flag
    else:
      flag.toJson()
  argsJson_2197825431.add block:
    when bool is JsonNode:
      value
    else:
      value.toJson()
  let argsJsonString = $argsJson_2197825431
  let res_2197825432 {.used.} = editor_setFlag_void_Editor_string_bool_wasm(
      argsJsonString.cstring)


proc editor_toggleFlag_void_Editor_string_wasm(arg_2197825562: cstring): cstring {.
    importc.}
proc toggleFlag*(flag: string) =
  var argsJson_2197825557 = newJArray()
  argsJson_2197825557.add block:
    when string is JsonNode:
      flag
    else:
      flag.toJson()
  let argsJsonString = $argsJson_2197825557
  let res_2197825558 {.used.} = editor_toggleFlag_void_Editor_string_wasm(
      argsJsonString.cstring)


proc editor_setOption_void_Editor_string_JsonNode_wasm(arg_2197825619: cstring): cstring {.
    importc.}
proc setOption*(option: string; value: JsonNode) =
  var argsJson_2197825614 = newJArray()
  argsJson_2197825614.add block:
    when string is JsonNode:
      option
    else:
      option.toJson()
  argsJson_2197825614.add block:
    when JsonNode is JsonNode:
      value
    else:
      value.toJson()
  let argsJsonString = $argsJson_2197825614
  let res_2197825615 {.used.} = editor_setOption_void_Editor_string_JsonNode_wasm(
      argsJsonString.cstring)


proc editor_quit_void_Editor_wasm(arg_2197825723: cstring): cstring {.importc.}
proc quit*() =
  var argsJson_2197825718 = newJArray()
  let argsJsonString = $argsJson_2197825718
  let res_2197825719 {.used.} = editor_quit_void_Editor_wasm(
      argsJsonString.cstring)


proc editor_changeFontSize_void_Editor_float32_wasm(arg_2197825772: cstring): cstring {.
    importc.}
proc changeFontSize*(amount: float32) =
  var argsJson_2197825767 = newJArray()
  argsJson_2197825767.add block:
    when float32 is JsonNode:
      amount
    else:
      amount.toJson()
  let argsJsonString = $argsJson_2197825767
  let res_2197825768 {.used.} = editor_changeFontSize_void_Editor_float32_wasm(
      argsJsonString.cstring)


proc editor_changeLayoutProp_void_Editor_string_float32_wasm(arg_2197825829: cstring): cstring {.
    importc.}
proc changeLayoutProp*(prop: string; change: float32) =
  var argsJson_2197825824 = newJArray()
  argsJson_2197825824.add block:
    when string is JsonNode:
      prop
    else:
      prop.toJson()
  argsJson_2197825824.add block:
    when float32 is JsonNode:
      change
    else:
      change.toJson()
  let argsJsonString = $argsJson_2197825824
  let res_2197825825 {.used.} = editor_changeLayoutProp_void_Editor_string_float32_wasm(
      argsJsonString.cstring)


proc editor_toggleStatusBarLocation_void_Editor_wasm(arg_2197826161: cstring): cstring {.
    importc.}
proc toggleStatusBarLocation*() =
  var argsJson_2197826156 = newJArray()
  let argsJsonString = $argsJson_2197826156
  let res_2197826157 {.used.} = editor_toggleStatusBarLocation_void_Editor_wasm(
      argsJsonString.cstring)


proc editor_createView_void_Editor_wasm(arg_2197826210: cstring): cstring {.
    importc.}
proc createView*() =
  var argsJson_2197826205 = newJArray()
  let argsJsonString = $argsJson_2197826205
  let res_2197826206 {.used.} = editor_createView_void_Editor_wasm(
      argsJsonString.cstring)


proc editor_closeCurrentView_void_Editor_wasm(arg_2197826292: cstring): cstring {.
    importc.}
proc closeCurrentView*() =
  var argsJson_2197826287 = newJArray()
  let argsJsonString = $argsJson_2197826287
  let res_2197826288 {.used.} = editor_closeCurrentView_void_Editor_wasm(
      argsJsonString.cstring)


proc editor_moveCurrentViewToTop_void_Editor_wasm(arg_2197826386: cstring): cstring {.
    importc.}
proc moveCurrentViewToTop*() =
  var argsJson_2197826381 = newJArray()
  let argsJsonString = $argsJson_2197826381
  let res_2197826382 {.used.} = editor_moveCurrentViewToTop_void_Editor_wasm(
      argsJsonString.cstring)


proc editor_nextView_void_Editor_wasm(arg_2197826486: cstring): cstring {.
    importc.}
proc nextView*() =
  var argsJson_2197826481 = newJArray()
  let argsJsonString = $argsJson_2197826481
  let res_2197826482 {.used.} = editor_nextView_void_Editor_wasm(
      argsJsonString.cstring)


proc editor_prevView_void_Editor_wasm(arg_2197826541: cstring): cstring {.
    importc.}
proc prevView*() =
  var argsJson_2197826536 = newJArray()
  let argsJsonString = $argsJson_2197826536
  let res_2197826537 {.used.} = editor_prevView_void_Editor_wasm(
      argsJsonString.cstring)


proc editor_moveCurrentViewPrev_void_Editor_wasm(arg_2197826599: cstring): cstring {.
    importc.}
proc moveCurrentViewPrev*() =
  var argsJson_2197826594 = newJArray()
  let argsJsonString = $argsJson_2197826594
  let res_2197826595 {.used.} = editor_moveCurrentViewPrev_void_Editor_wasm(
      argsJsonString.cstring)


proc editor_moveCurrentViewNext_void_Editor_wasm(arg_2197826671: cstring): cstring {.
    importc.}
proc moveCurrentViewNext*() =
  var argsJson_2197826666 = newJArray()
  let argsJsonString = $argsJson_2197826666
  let res_2197826667 {.used.} = editor_moveCurrentViewNext_void_Editor_wasm(
      argsJsonString.cstring)


proc editor_setLayout_void_Editor_string_wasm(arg_2197826740: cstring): cstring {.
    importc.}
proc setLayout*(layout: string) =
  var argsJson_2197826735 = newJArray()
  argsJson_2197826735.add block:
    when string is JsonNode:
      layout
    else:
      layout.toJson()
  let argsJsonString = $argsJson_2197826735
  let res_2197826736 {.used.} = editor_setLayout_void_Editor_string_wasm(
      argsJsonString.cstring)


proc editor_commandLine_void_Editor_string_wasm(arg_2197826833: cstring): cstring {.
    importc.}
proc commandLine*(initialValue: string = "") =
  var argsJson_2197826828 = newJArray()
  argsJson_2197826828.add block:
    when string is JsonNode:
      initialValue
    else:
      initialValue.toJson()
  let argsJsonString = $argsJson_2197826828
  let res_2197826829 {.used.} = editor_commandLine_void_Editor_string_wasm(
      argsJsonString.cstring)


proc editor_exitCommandLine_void_Editor_wasm(arg_2197826894: cstring): cstring {.
    importc.}
proc exitCommandLine*() =
  var argsJson_2197826889 = newJArray()
  let argsJsonString = $argsJson_2197826889
  let res_2197826890 {.used.} = editor_exitCommandLine_void_Editor_wasm(
      argsJsonString.cstring)


proc editor_executeCommandLine_bool_Editor_wasm(arg_2197826947: cstring): cstring {.
    importc.}
proc executeCommandLine*(): bool =
  var argsJson_2197826942 = newJArray()
  let argsJsonString = $argsJson_2197826942
  let res_2197826943 {.used.} = editor_executeCommandLine_bool_Editor_wasm(
      argsJsonString.cstring)
  result = parseJson($res_2197826943).jsonTo(typeof(result))


proc editor_writeFile_void_Editor_string_bool_wasm(arg_2197827129: cstring): cstring {.
    importc.}
proc writeFile*(path: string = ""; app: bool = false) =
  var argsJson_2197827124 = newJArray()
  argsJson_2197827124.add block:
    when string is JsonNode:
      path
    else:
      path.toJson()
  argsJson_2197827124.add block:
    when bool is JsonNode:
      app
    else:
      app.toJson()
  let argsJsonString = $argsJson_2197827124
  let res_2197827125 {.used.} = editor_writeFile_void_Editor_string_bool_wasm(
      argsJsonString.cstring)


proc editor_loadFile_void_Editor_string_wasm(arg_2197827206: cstring): cstring {.
    importc.}
proc loadFile*(path: string = "") =
  var argsJson_2197827201 = newJArray()
  argsJson_2197827201.add block:
    when string is JsonNode:
      path
    else:
      path.toJson()
  let argsJsonString = $argsJson_2197827201
  let res_2197827202 {.used.} = editor_loadFile_void_Editor_string_wasm(
      argsJsonString.cstring)


proc editor_openFile_void_Editor_string_bool_wasm(arg_2197827294: cstring): cstring {.
    importc.}
proc openFile*(path: string; app: bool = false) =
  var argsJson_2197827289 = newJArray()
  argsJson_2197827289.add block:
    when string is JsonNode:
      path
    else:
      path.toJson()
  argsJson_2197827289.add block:
    when bool is JsonNode:
      app
    else:
      app.toJson()
  let argsJsonString = $argsJson_2197827289
  let res_2197827290 {.used.} = editor_openFile_void_Editor_string_bool_wasm(
      argsJsonString.cstring)


proc editor_removeFromLocalStorage_void_Editor_wasm(arg_2197827478: cstring): cstring {.
    importc.}
proc removeFromLocalStorage*() =
  var argsJson_2197827473 = newJArray()
  let argsJsonString = $argsJson_2197827473
  let res_2197827474 {.used.} = editor_removeFromLocalStorage_void_Editor_wasm(
      argsJsonString.cstring)


proc editor_loadTheme_void_Editor_string_wasm(arg_2197827527: cstring): cstring {.
    importc.}
proc loadTheme*(name: string) =
  var argsJson_2197827522 = newJArray()
  argsJson_2197827522.add block:
    when string is JsonNode:
      name
    else:
      name.toJson()
  let argsJsonString = $argsJson_2197827522
  let res_2197827523 {.used.} = editor_loadTheme_void_Editor_string_wasm(
      argsJsonString.cstring)


proc editor_chooseTheme_void_Editor_wasm(arg_2197827620: cstring): cstring {.
    importc.}
proc chooseTheme*() =
  var argsJson_2197827615 = newJArray()
  let argsJsonString = $argsJson_2197827615
  let res_2197827616 {.used.} = editor_chooseTheme_void_Editor_wasm(
      argsJsonString.cstring)


proc editor_chooseFile_void_Editor_string_wasm(arg_2197828318: cstring): cstring {.
    importc.}
proc chooseFile*(view: string = "new") =
  var argsJson_2197828313 = newJArray()
  argsJson_2197828313.add block:
    when string is JsonNode:
      view
    else:
      view.toJson()
  let argsJsonString = $argsJson_2197828313
  let res_2197828314 {.used.} = editor_chooseFile_void_Editor_string_wasm(
      argsJsonString.cstring)


proc editor_setGithubAccessToken_void_Editor_string_wasm(arg_2197828881: cstring): cstring {.
    importc.}
proc setGithubAccessToken*(token: string) =
  var argsJson_2197828876 = newJArray()
  argsJson_2197828876.add block:
    when string is JsonNode:
      token
    else:
      token.toJson()
  let argsJsonString = $argsJson_2197828876
  let res_2197828877 {.used.} = editor_setGithubAccessToken_void_Editor_string_wasm(
      argsJsonString.cstring)


proc editor_reloadConfig_void_Editor_wasm(arg_2197828938: cstring): cstring {.
    importc.}
proc reloadConfig*() =
  var argsJson_2197828933 = newJArray()
  let argsJsonString = $argsJson_2197828933
  let res_2197828934 {.used.} = editor_reloadConfig_void_Editor_wasm(
      argsJsonString.cstring)


proc editor_logOptions_void_Editor_wasm(arg_2197829029: cstring): cstring {.
    importc.}
proc logOptions*() =
  var argsJson_2197829024 = newJArray()
  let argsJsonString = $argsJson_2197829024
  let res_2197829025 {.used.} = editor_logOptions_void_Editor_wasm(
      argsJsonString.cstring)


proc editor_clearCommands_void_Editor_string_wasm(arg_2197829078: cstring): cstring {.
    importc.}
proc clearCommands*(context: string) =
  var argsJson_2197829073 = newJArray()
  argsJson_2197829073.add block:
    when string is JsonNode:
      context
    else:
      context.toJson()
  let argsJsonString = $argsJson_2197829073
  let res_2197829074 {.used.} = editor_clearCommands_void_Editor_string_wasm(
      argsJsonString.cstring)


proc editor_getAllEditors_seq_EditorId_Editor_wasm(arg_2197829135: cstring): cstring {.
    importc.}
proc getAllEditors*(): seq[EditorId] =
  var argsJson_2197829130 = newJArray()
  let argsJsonString = $argsJson_2197829130
  let res_2197829131 {.used.} = editor_getAllEditors_seq_EditorId_Editor_wasm(
      argsJsonString.cstring)
  result = parseJson($res_2197829131).jsonTo(typeof(result))


proc editor_setMode_void_Editor_string_wasm(arg_2197829460: cstring): cstring {.
    importc.}
proc setMode*(mode: string) =
  var argsJson_2197829455 = newJArray()
  argsJson_2197829455.add block:
    when string is JsonNode:
      mode
    else:
      mode.toJson()
  let argsJsonString = $argsJson_2197829455
  let res_2197829456 {.used.} = editor_setMode_void_Editor_string_wasm(
      argsJsonString.cstring)


proc editor_mode_string_Editor_wasm(arg_2197829575: cstring): cstring {.importc.}
proc mode*(): string =
  var argsJson_2197829570 = newJArray()
  let argsJsonString = $argsJson_2197829570
  let res_2197829571 {.used.} = editor_mode_string_Editor_wasm(
      argsJsonString.cstring)
  result = parseJson($res_2197829571).jsonTo(typeof(result))


proc editor_getContextWithMode_string_Editor_string_wasm(arg_2197829630: cstring): cstring {.
    importc.}
proc getContextWithMode*(context: string): string =
  var argsJson_2197829625 = newJArray()
  argsJson_2197829625.add block:
    when string is JsonNode:
      context
    else:
      context.toJson()
  let argsJsonString = $argsJson_2197829625
  let res_2197829626 {.used.} = editor_getContextWithMode_string_Editor_string_wasm(
      argsJsonString.cstring)
  result = parseJson($res_2197829626).jsonTo(typeof(result))


proc editor_scriptRunAction_void_string_string_wasm(arg_2197829919: cstring): cstring {.
    importc.}
proc scriptRunAction*(action: string; arg: string) =
  var argsJson_2197829915 = newJArray()
  argsJson_2197829915.add block:
    when string is JsonNode:
      action
    else:
      action.toJson()
  argsJson_2197829915.add block:
    when string is JsonNode:
      arg
    else:
      arg.toJson()
  let argsJsonString = $argsJson_2197829915
  let res_2197829916 {.used.} = editor_scriptRunAction_void_string_string_wasm(
      argsJsonString.cstring)


proc editor_scriptLog_void_string_wasm(arg_2197829961: cstring): cstring {.
    importc.}
proc scriptLog*(message: string) =
  var argsJson_2197829957 = newJArray()
  argsJson_2197829957.add block:
    when string is JsonNode:
      message
    else:
      message.toJson()
  let argsJsonString = $argsJson_2197829957
  let res_2197829958 {.used.} = editor_scriptLog_void_string_wasm(
      argsJsonString.cstring)


proc editor_addCommandScript_void_Editor_string_string_string_string_wasm(
    arg_2197829998: cstring): cstring {.importc.}
proc addCommandScript*(context: string; keys: string; action: string;
                       arg: string = "") =
  var argsJson_2197829993 = newJArray()
  argsJson_2197829993.add block:
    when string is JsonNode:
      context
    else:
      context.toJson()
  argsJson_2197829993.add block:
    when string is JsonNode:
      keys
    else:
      keys.toJson()
  argsJson_2197829993.add block:
    when string is JsonNode:
      action
    else:
      action.toJson()
  argsJson_2197829993.add block:
    when string is JsonNode:
      arg
    else:
      arg.toJson()
  let argsJsonString = $argsJson_2197829993
  let res_2197829994 {.used.} = editor_addCommandScript_void_Editor_string_string_string_string_wasm(
      argsJsonString.cstring)


proc editor_removeCommand_void_Editor_string_string_wasm(arg_2197830080: cstring): cstring {.
    importc.}
proc removeCommand*(context: string; keys: string) =
  var argsJson_2197830075 = newJArray()
  argsJson_2197830075.add block:
    when string is JsonNode:
      context
    else:
      context.toJson()
  argsJson_2197830075.add block:
    when string is JsonNode:
      keys
    else:
      keys.toJson()
  let argsJsonString = $argsJson_2197830075
  let res_2197830076 {.used.} = editor_removeCommand_void_Editor_string_string_wasm(
      argsJsonString.cstring)


proc editor_getActivePopup_EditorId_wasm(arg_2197830144: cstring): cstring {.
    importc.}
proc getActivePopup*(): EditorId =
  var argsJson_2197830140 = newJArray()
  let argsJsonString = $argsJson_2197830140
  let res_2197830141 {.used.} = editor_getActivePopup_EditorId_wasm(
      argsJsonString.cstring)
  result = parseJson($res_2197830141).jsonTo(typeof(result))


proc editor_getActiveEditor_EditorId_wasm(arg_2197830185: cstring): cstring {.
    importc.}
proc getActiveEditor*(): EditorId =
  var argsJson_2197830181 = newJArray()
  let argsJsonString = $argsJson_2197830181
  let res_2197830182 {.used.} = editor_getActiveEditor_EditorId_wasm(
      argsJsonString.cstring)
  result = parseJson($res_2197830182).jsonTo(typeof(result))


proc editor_getActiveEditor2_EditorId_Editor_wasm(arg_2197830221: cstring): cstring {.
    importc.}
proc getActiveEditor2*(): EditorId =
  var argsJson_2197830216 = newJArray()
  let argsJsonString = $argsJson_2197830216
  let res_2197830217 {.used.} = editor_getActiveEditor2_EditorId_Editor_wasm(
      argsJsonString.cstring)
  result = parseJson($res_2197830217).jsonTo(typeof(result))


proc editor_loadCurrentConfig_void_Editor_wasm(arg_2197830276: cstring): cstring {.
    importc.}
proc loadCurrentConfig*() =
  var argsJson_2197830271 = newJArray()
  let argsJsonString = $argsJson_2197830271
  let res_2197830272 {.used.} = editor_loadCurrentConfig_void_Editor_wasm(
      argsJsonString.cstring)


proc editor_sourceCurrentDocument_void_Editor_wasm(arg_2197830325: cstring): cstring {.
    importc.}
proc sourceCurrentDocument*() =
  var argsJson_2197830320 = newJArray()
  let argsJsonString = $argsJson_2197830320
  let res_2197830321 {.used.} = editor_sourceCurrentDocument_void_Editor_wasm(
      argsJsonString.cstring)


proc editor_getEditor_EditorId_int_wasm(arg_2197830373: cstring): cstring {.
    importc.}
proc getEditor*(index: int): EditorId =
  var argsJson_2197830369 = newJArray()
  argsJson_2197830369.add block:
    when int is JsonNode:
      index
    else:
      index.toJson()
  let argsJsonString = $argsJson_2197830369
  let res_2197830370 {.used.} = editor_getEditor_EditorId_int_wasm(
      argsJsonString.cstring)
  result = parseJson($res_2197830370).jsonTo(typeof(result))


proc editor_scriptIsTextEditor_bool_EditorId_wasm(arg_2197830416: cstring): cstring {.
    importc.}
proc scriptIsTextEditor*(editorId: EditorId): bool =
  var argsJson_2197830412 = newJArray()
  argsJson_2197830412.add block:
    when EditorId is JsonNode:
      editorId
    else:
      editorId.toJson()
  let argsJsonString = $argsJson_2197830412
  let res_2197830413 {.used.} = editor_scriptIsTextEditor_bool_EditorId_wasm(
      argsJsonString.cstring)
  result = parseJson($res_2197830413).jsonTo(typeof(result))


proc editor_scriptIsAstEditor_bool_EditorId_wasm(arg_2197830488: cstring): cstring {.
    importc.}
proc scriptIsAstEditor*(editorId: EditorId): bool =
  var argsJson_2197830484 = newJArray()
  argsJson_2197830484.add block:
    when EditorId is JsonNode:
      editorId
    else:
      editorId.toJson()
  let argsJsonString = $argsJson_2197830484
  let res_2197830485 {.used.} = editor_scriptIsAstEditor_bool_EditorId_wasm(
      argsJsonString.cstring)
  result = parseJson($res_2197830485).jsonTo(typeof(result))


proc editor_scriptIsModelEditor_bool_EditorId_wasm(arg_2197830560: cstring): cstring {.
    importc.}
proc scriptIsModelEditor*(editorId: EditorId): bool =
  var argsJson_2197830556 = newJArray()
  argsJson_2197830556.add block:
    when EditorId is JsonNode:
      editorId
    else:
      editorId.toJson()
  let argsJsonString = $argsJson_2197830556
  let res_2197830557 {.used.} = editor_scriptIsModelEditor_bool_EditorId_wasm(
      argsJsonString.cstring)
  result = parseJson($res_2197830557).jsonTo(typeof(result))


proc editor_scriptRunActionFor_void_EditorId_string_string_wasm(arg_2197830632: cstring): cstring {.
    importc.}
proc scriptRunActionFor*(editorId: EditorId; action: string; arg: string) =
  var argsJson_2197830628 = newJArray()
  argsJson_2197830628.add block:
    when EditorId is JsonNode:
      editorId
    else:
      editorId.toJson()
  argsJson_2197830628.add block:
    when string is JsonNode:
      action
    else:
      action.toJson()
  argsJson_2197830628.add block:
    when string is JsonNode:
      arg
    else:
      arg.toJson()
  let argsJsonString = $argsJson_2197830628
  let res_2197830629 {.used.} = editor_scriptRunActionFor_void_EditorId_string_string_wasm(
      argsJsonString.cstring)


proc editor_scriptInsertTextInto_void_EditorId_string_wasm(arg_2197830738: cstring): cstring {.
    importc.}
proc scriptInsertTextInto*(editorId: EditorId; text: string) =
  var argsJson_2197830734 = newJArray()
  argsJson_2197830734.add block:
    when EditorId is JsonNode:
      editorId
    else:
      editorId.toJson()
  argsJson_2197830734.add block:
    when string is JsonNode:
      text
    else:
      text.toJson()
  let argsJsonString = $argsJson_2197830734
  let res_2197830735 {.used.} = editor_scriptInsertTextInto_void_EditorId_string_wasm(
      argsJsonString.cstring)


proc editor_scriptTextEditorSelection_Selection_EditorId_wasm(arg_2197830808: cstring): cstring {.
    importc.}
proc scriptTextEditorSelection*(editorId: EditorId): Selection =
  var argsJson_2197830804 = newJArray()
  argsJson_2197830804.add block:
    when EditorId is JsonNode:
      editorId
    else:
      editorId.toJson()
  let argsJsonString = $argsJson_2197830804
  let res_2197830805 {.used.} = editor_scriptTextEditorSelection_Selection_EditorId_wasm(
      argsJsonString.cstring)
  result = parseJson($res_2197830805).jsonTo(typeof(result))


proc editor_scriptSetTextEditorSelection_void_EditorId_Selection_wasm(
    arg_2197830885: cstring): cstring {.importc.}
proc scriptSetTextEditorSelection*(editorId: EditorId; selection: Selection) =
  var argsJson_2197830881 = newJArray()
  argsJson_2197830881.add block:
    when EditorId is JsonNode:
      editorId
    else:
      editorId.toJson()
  argsJson_2197830881.add block:
    when Selection is JsonNode:
      selection
    else:
      selection.toJson()
  let argsJsonString = $argsJson_2197830881
  let res_2197830882 {.used.} = editor_scriptSetTextEditorSelection_void_EditorId_Selection_wasm(
      argsJsonString.cstring)


proc editor_scriptTextEditorSelections_seq_Selection_EditorId_wasm(arg_2197830959: cstring): cstring {.
    importc.}
proc scriptTextEditorSelections*(editorId: EditorId): seq[Selection] =
  var argsJson_2197830955 = newJArray()
  argsJson_2197830955.add block:
    when EditorId is JsonNode:
      editorId
    else:
      editorId.toJson()
  let argsJsonString = $argsJson_2197830955
  let res_2197830956 {.used.} = editor_scriptTextEditorSelections_seq_Selection_EditorId_wasm(
      argsJsonString.cstring)
  result = parseJson($res_2197830956).jsonTo(typeof(result))


proc editor_scriptSetTextEditorSelections_void_EditorId_seq_Selection_wasm(
    arg_2197831040: cstring): cstring {.importc.}
proc scriptSetTextEditorSelections*(editorId: EditorId;
                                    selections: seq[Selection]) =
  var argsJson_2197831036 = newJArray()
  argsJson_2197831036.add block:
    when EditorId is JsonNode:
      editorId
    else:
      editorId.toJson()
  argsJson_2197831036.add block:
    when seq[Selection] is JsonNode:
      selections
    else:
      selections.toJson()
  let argsJsonString = $argsJson_2197831036
  let res_2197831037 {.used.} = editor_scriptSetTextEditorSelections_void_EditorId_seq_Selection_wasm(
      argsJsonString.cstring)


proc editor_scriptGetTextEditorLine_string_EditorId_int_wasm(arg_2197831114: cstring): cstring {.
    importc.}
proc scriptGetTextEditorLine*(editorId: EditorId; line: int): string =
  var argsJson_2197831110 = newJArray()
  argsJson_2197831110.add block:
    when EditorId is JsonNode:
      editorId
    else:
      editorId.toJson()
  argsJson_2197831110.add block:
    when int is JsonNode:
      line
    else:
      line.toJson()
  let argsJsonString = $argsJson_2197831110
  let res_2197831111 {.used.} = editor_scriptGetTextEditorLine_string_EditorId_int_wasm(
      argsJsonString.cstring)
  result = parseJson($res_2197831111).jsonTo(typeof(result))


proc editor_scriptGetTextEditorLineCount_int_EditorId_wasm(arg_2197831198: cstring): cstring {.
    importc.}
proc scriptGetTextEditorLineCount*(editorId: EditorId): int =
  var argsJson_2197831194 = newJArray()
  argsJson_2197831194.add block:
    when EditorId is JsonNode:
      editorId
    else:
      editorId.toJson()
  let argsJsonString = $argsJson_2197831194
  let res_2197831195 {.used.} = editor_scriptGetTextEditorLineCount_int_EditorId_wasm(
      argsJsonString.cstring)
  result = parseJson($res_2197831195).jsonTo(typeof(result))


proc editor_scriptGetOptionInt_int_string_int_wasm(arg_2197831285: cstring): cstring {.
    importc.}
proc scriptGetOptionInt*(path: string; default: int): int =
  var argsJson_2197831281 = newJArray()
  argsJson_2197831281.add block:
    when string is JsonNode:
      path
    else:
      path.toJson()
  argsJson_2197831281.add block:
    when int is JsonNode:
      default
    else:
      default.toJson()
  let argsJsonString = $argsJson_2197831281
  let res_2197831282 {.used.} = editor_scriptGetOptionInt_int_string_int_wasm(
      argsJsonString.cstring)
  result = parseJson($res_2197831282).jsonTo(typeof(result))


proc editor_scriptGetOptionFloat_float_string_float_wasm(arg_2197831339: cstring): cstring {.
    importc.}
proc scriptGetOptionFloat*(path: string; default: float): float =
  var argsJson_2197831335 = newJArray()
  argsJson_2197831335.add block:
    when string is JsonNode:
      path
    else:
      path.toJson()
  argsJson_2197831335.add block:
    when float is JsonNode:
      default
    else:
      default.toJson()
  let argsJsonString = $argsJson_2197831335
  let res_2197831336 {.used.} = editor_scriptGetOptionFloat_float_string_float_wasm(
      argsJsonString.cstring)
  result = parseJson($res_2197831336).jsonTo(typeof(result))


proc editor_scriptGetOptionBool_bool_string_bool_wasm(arg_2197831451: cstring): cstring {.
    importc.}
proc scriptGetOptionBool*(path: string; default: bool): bool =
  var argsJson_2197831447 = newJArray()
  argsJson_2197831447.add block:
    when string is JsonNode:
      path
    else:
      path.toJson()
  argsJson_2197831447.add block:
    when bool is JsonNode:
      default
    else:
      default.toJson()
  let argsJsonString = $argsJson_2197831447
  let res_2197831448 {.used.} = editor_scriptGetOptionBool_bool_string_bool_wasm(
      argsJsonString.cstring)
  result = parseJson($res_2197831448).jsonTo(typeof(result))


proc editor_scriptGetOptionString_string_string_string_wasm(arg_2197831505: cstring): cstring {.
    importc.}
proc scriptGetOptionString*(path: string; default: string): string =
  var argsJson_2197831501 = newJArray()
  argsJson_2197831501.add block:
    when string is JsonNode:
      path
    else:
      path.toJson()
  argsJson_2197831501.add block:
    when string is JsonNode:
      default
    else:
      default.toJson()
  let argsJsonString = $argsJson_2197831501
  let res_2197831502 {.used.} = editor_scriptGetOptionString_string_string_string_wasm(
      argsJsonString.cstring)
  result = parseJson($res_2197831502).jsonTo(typeof(result))


proc editor_scriptSetOptionInt_void_string_int_wasm(arg_2197831559: cstring): cstring {.
    importc.}
proc scriptSetOptionInt*(path: string; value: int) =
  var argsJson_2197831555 = newJArray()
  argsJson_2197831555.add block:
    when string is JsonNode:
      path
    else:
      path.toJson()
  argsJson_2197831555.add block:
    when int is JsonNode:
      value
    else:
      value.toJson()
  let argsJsonString = $argsJson_2197831555
  let res_2197831556 {.used.} = editor_scriptSetOptionInt_void_string_int_wasm(
      argsJsonString.cstring)


proc editor_scriptSetOptionFloat_void_string_float_wasm(arg_2197831646: cstring): cstring {.
    importc.}
proc scriptSetOptionFloat*(path: string; value: float) =
  var argsJson_2197831642 = newJArray()
  argsJson_2197831642.add block:
    when string is JsonNode:
      path
    else:
      path.toJson()
  argsJson_2197831642.add block:
    when float is JsonNode:
      value
    else:
      value.toJson()
  let argsJsonString = $argsJson_2197831642
  let res_2197831643 {.used.} = editor_scriptSetOptionFloat_void_string_float_wasm(
      argsJsonString.cstring)


proc editor_scriptSetOptionBool_void_string_bool_wasm(arg_2197831733: cstring): cstring {.
    importc.}
proc scriptSetOptionBool*(path: string; value: bool) =
  var argsJson_2197831729 = newJArray()
  argsJson_2197831729.add block:
    when string is JsonNode:
      path
    else:
      path.toJson()
  argsJson_2197831729.add block:
    when bool is JsonNode:
      value
    else:
      value.toJson()
  let argsJsonString = $argsJson_2197831729
  let res_2197831730 {.used.} = editor_scriptSetOptionBool_void_string_bool_wasm(
      argsJsonString.cstring)


proc editor_scriptSetOptionString_void_string_string_wasm(arg_2197831820: cstring): cstring {.
    importc.}
proc scriptSetOptionString*(path: string; value: string) =
  var argsJson_2197831816 = newJArray()
  argsJson_2197831816.add block:
    when string is JsonNode:
      path
    else:
      path.toJson()
  argsJson_2197831816.add block:
    when string is JsonNode:
      value
    else:
      value.toJson()
  let argsJsonString = $argsJson_2197831816
  let res_2197831817 {.used.} = editor_scriptSetOptionString_void_string_string_wasm(
      argsJsonString.cstring)


proc editor_scriptSetCallback_void_string_int_wasm(arg_2197831907: cstring): cstring {.
    importc.}
proc scriptSetCallback*(path: string; id: int) =
  var argsJson_2197831903 = newJArray()
  argsJson_2197831903.add block:
    when string is JsonNode:
      path
    else:
      path.toJson()
  argsJson_2197831903.add block:
    when int is JsonNode:
      id
    else:
      id.toJson()
  let argsJsonString = $argsJson_2197831903
  let res_2197831904 {.used.} = editor_scriptSetCallback_void_string_int_wasm(
      argsJsonString.cstring)

