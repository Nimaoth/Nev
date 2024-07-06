import absytree_runtime

import std/[strutils, unicode, tables, json, options, genasts, macros]
import misc/[util, myjsonutils]

type

  HarpoonPartialConfigItem = object
    selectWithNil: Option[bool]
    # encode: Option[proc(item: HarpoonItem): string]
    # decode: Option[proc(obj: string): HarpoonItem]
    # display: Option[proc(obj: HarpoonItem): string]
    # select: Option[proc(item: HarpoonItem, list: HarpoonList, options: JsonNode)]
    # equals: Option[proc(itemA: HarpoonItem, itemB: HarpoonItem): bool]
    # createListItem: Option[proc(config: HarpoonPartialConfigItem, item: JsonNode): HarpoonItem]
    # onBeforeLeave: Option[proc(editor: EditorId, list3: HarpoonList)]
    # onAfterLeave: Option[proc(editor: EditorId, list3: HarpoonList)]
    # getRootDir: Option[proc(): string]
    encode: Option[string]
    decode: Option[string]
    display: Option[string]
    select: Option[string]
    equals: Option[string]
    createListItem: Option[string]
    onBeforeLeave: Option[string]
    onAfterLeave: Option[string]
    getRootDir: Option[string]

  HarpoonPartialSettings = object
    saveOnToggle: Option[bool]
    syncOnUIClose: Option[bool]
    # key: Option[proc(): string]
    keyCallback: Option[string]

  HarpoonSettings = object
    saveOnToggle: bool
    syncOnUIClose: bool
    # key: proc(): string
    keyCallback: string

  HarpoonPartialConfig = object
    default: Option[HarpoonPartialConfigItem]
    settings: Option[HarpoonPartialSettings]
    extra: Table[string, HarpoonPartialConfigItem]

  HarpoonConfig = object
    default: HarpoonPartialConfigItem
    settings: HarpoonSettings
    extra: Table[string, HarpoonPartialConfigItem]

  HarpoonUI = object

  HarpoonExtensions = object

  HarpoonData = object

  HarpoonLog = object

  HarpoonItem = object
    value: string
    context: JsonNode

  HarpoonList = object
    name: string
    items: seq[HarpoonItem]
    config: HarpoonPartialConfigItem

  Harpoon = ref object
    config: HarpoonConfig
    ui: HarpoonUI
    extensions: HarpoonExtensions
    data: HarpoonData
    logger: HarpoonLog
    lists: Table[string, Table[string, HarpoonList]]
    hooksSetup: bool

const DEFAULT_LIST = "__harpoon_files"

proc postInitialize*(): bool {.wasmexport.} =
  return true

proc sync()

template override(name: untyped): untyped =
  result.name = partialConfig.name.get(config.name)

proc merge(config: HarpoonPartialConfigItem, partialConfig: HarpoonPartialConfigItem): HarpoonPartialConfigItem =
  result = config

  template override(name: untyped): untyped =
    if partialConfig.name.isSome:
      result.name = partialConfig.name

  override(selectWithNil)
  override(encode)
  override(decode)
  override(display)
  override(select)
  override(equals)
  override(createListItem)
  override(onBeforeLeave)
  override(onAfterLeave)
  override(getRootDir)

proc merge(settings: HarpoonSettings, partialSettings: HarpoonPartialSettings): HarpoonSettings =
  result = settings

  template override(name: untyped): untyped =
    if partialSettings.name.isSome:
      result.name = partialSettings.name.get

  override(saveOnToggle)
  override(syncOnUIClose)
  override(keyCallback)

macro invoke(callback: untyped, output: untyped, args: varargs[untyped]): untyped =
  var result = nnkStmtList.newTree()

  var arr = genSym(nskVar, "args")

  let varArr = genAst(arr):
    var arr = newJArray()
  result.add varArr

  for a in args:
    let arg = genAst(arr, a):
      arr.add a.toJson()

    result.add arg

  var jsonToCall = genAst(callback, arr, output):
    let json = callScriptAction(callback, arr)
    output = json.jsonTo(typeof(output))

  result.add jsonToCall

macro invokeVoid(callback: untyped, args: varargs[untyped]): untyped =
  var result = nnkStmtList.newTree()

  var arr = genSym(nskVar, "args")

  let varArr = genAst(arr):
    var arr = newJArray()
  result.add varArr

  for a in args:
    let arg = genAst(arr, a):
      arr.add a.toJson()

    result.add arg

  var jsonToCall = genAst(callback, arr):
    discard callScriptAction(callback, arr)

  result.add jsonToCall

proc merge(config: HarpoonConfig, partialConfig: HarpoonPartialConfig): HarpoonConfig =
  result = config
  if partialConfig.default.isSome:
    result.default = result.default.merge(partialConfig.default.get)
  if partialConfig.settings.isSome:
    result.settings = result.settings.merge(partialConfig.settings.get)

  # todo: override or merge individual HarpoonPartialConfigItem?
  for key, value in partialConfig.extra.pairs:
    result.extra[key] = value

proc defaultHarpoonConfig(): HarpoonConfig =
  result = HarpoonConfig()

proc defaultEncode(item: HarpoonItem): string =
  return $item.toJson

proc defaultDecode(value: string): HarpoonItem =
  return value.parseJson.jsonTo(HarpoonItem)

proc defaultCreateListItem(config: HarpoonPartialConfigItem, name: Option[string]): HarpoonItem =
  let activeEditor = if getActiveEditor().isTextEditor(ed):
      ed
    else:
      return

  let name = name.getOr:
    activeEditor.getFileName()

  let cursor = activeEditor.selection.last
  result = HarpoonItem(
    value: name,
    context: cursor.toJson
  )

proc defaultSelect(item: HarpoonItem, list: HarpoonList, options: JsonNode) =
  infof"defaultSelect: {item}, {options}"
  if item.value == "" and item.context == nil:
    return

  if getExistingEditor(item.value).getSome(editor):
    editor.showEditor()
  else:
    let editor = getOrOpenEditor(item.value).getOr:
      infof"[harpoon] Failed to open editor for {item.value}"
      return
    editor.showEditor()
    if editor.isTextEditor(ed):
      let cursor = item.context.jsonTo(Cursor)
      ed.targetSelection = cursor.toSelection

proc get(self: HarpoonData, key: string, name: string): seq[string] =
  return getSessionData[seq[string]](&"harpoon.{key}.{name}", @[])

proc update(data: HarpoonData, key: string, name: string, encoded: seq[string]) =
  setSessionData(&"harpoon.{key}.{name}", encoded.toJson)

proc sync(data: HarpoonData) =
  discard

proc get(config: HarpoonConfig, name: string): HarpoonPartialConfigItem =
  if config.extra.contains(name):
    return config.extra[name]
  return config.default

proc encode(list: HarpoonList): Option[seq[string]] =
  let encodeCallback = list.config.encode.get("")

  var res: seq[string] = @[]
  for item in list.items:
    var encoded = ""
    if encodeCallback != "":
      encodeCallback.invoke(encoded, item)
    else:
      encoded = defaultEncode(item)

    res.add encoded

  res.some

proc decode(config: HarpoonPartialConfigItem, name: string, items: seq[string]): HarpoonList =
  result = HarpoonList(name: name, config: config)
  for item in items:
    var harpoonItem: HarpoonItem
    if config.decode.getSome(decode) and decode != "":
      decode.invoke(harpoonItem, item)
    else:
      harpoonItem = defaultDecode(item)
    result.items.add harpoonItem

proc getList(self: Harpoon, name: Option[string] = string.none): var HarpoonList =
  let name = name.get DEFAULT_LIST

  var key: string
  if self.config.settings.keyCallback != "":
    self.config.settings.keyCallback.invoke(key)
  else:
    key = ""

  let lists = self.lists.mgetOrPut(key).addr

  if lists[].contains(name):
    return self.lists[key][name]

  let data = self.data.get(key, name)
  let listConfig = self.config.get(name)
  let list = listConfig.decode(name, data)
  lists[][name] = list

  self.lists[key][name]

var gHarpoon: Harpoon = nil

proc dumpState() {.expose("harpoon-dump-state").} =
  infof"{gHarpoon[]}"
  infof"{gHarpoon[].toJson.pretty}"
  infof"Lists:"
  for key, lists in gHarpoon.lists.pairs:
    infof"  [{key}]"
    for name, list in lists.pairs:
      infof"  [{name}]: {list.name}, {list.config}"
      for k, item in list.items:
        infof"    [{k}]: {item}"

proc listAdd(list: Option[string] = string.none, name: Option[string] = string.none) {.expose("harpoon-list-add").} =
  infof"[harpoon] listAdd: {list}, {name}"

  var list = gHarpoon.getList(list).addr

  var item: HarpoonItem
  if list[].config.createListItem.isSome:
    list[].config.createListItem.get.invoke(item, list[].config, name)
  else:
    item = defaultCreateListItem(list[].config, name)

  list[].items.add item

  sync()
  dumpState()

proc listSet(index: int, list: Option[string] = string.none, name: Option[string] = string.none) {.expose("harpoon-list-set").} =
  infof"[harpoon] listSet: {index}, {list}, {name}"

  var list = gHarpoon.getList(list).addr

  var item: HarpoonItem
  if list[].config.createListItem.isSome:
    list[].config.createListItem.get.invoke(item, list[].config, name)
  else:
    item = defaultCreateListItem(list[].config, name)

  while list[].items.len <= index:
    list[].items.add HarpoonItem()

  list[].items[index] = item

  sync()
  dumpState()

proc listSelect(index: int, list: Option[string] = string.none, options: JsonNode = newJNull()) {.expose("harpoon-list-select").} =
  infof"[harpoon] listSelect: {index}, {list}, {options}"

  var list = gHarpoon.getList(list).addr
  infof"[harpoon] listSelect: {list[]}"

  if index notin 0..list[].items.high:
    return

  if list[].config.select.getSome(callback):
    callback.invokeVoid(list[].items[index], list[], options)
  else:
    defaultSelect(list[].items[index], list[], options)

proc setup(partialConfig: JsonNode) {.expose("harpoon-setup").} =
  let partialConfig = partialConfig.jsonTo(HarpoonPartialConfig, JOptions(allowMissingKeys: true)).catch:
    infof"[harpoon] Failed to parse config: {getCurrentExceptionMsg()}: {partialConfig.pretty}"
    return

  gHarpoon = Harpoon()
  gHarpoon.config = defaultHarpoonConfig().merge(partialConfig)

  infof"[harpoon] Setup successfull. Config: {gHarpoon.config}"

proc getConfig(config: HarpoonConfig, name: string): HarpoonPartialConfigItem =
  if config.extra.contains(name):
    return config.extra[name]
  return config.default

iterator allLists(self: Harpoon): tuple[key: string, name: string, list: ptr HarpoonList] =
  for key, lists in self.lists.mpairs:
    for name, list in lists.mpairs:
      yield (key, name, list.addr)

proc sync() {.expose("harpoon-sync").} =
  infof"[harpoon] sync"
  for (key, name, list) in gHarpoon.allLists:
    infof"{key}, {name}, {list[]}"
    if list[].encode().getSome(encoded):
      gHarpoon.data.update(key, name, encoded)

  gHarpoon.data.sync()

setup(newJObject())

# var list = gHarpoon.getList(string.none).addr

# list[].items.add HarpoonItem(
#   value: "C:/Absytree/src/platform/tui.nim",
#   context: (10, 0).Cursor.toJson,
# )

# list[].items.add HarpoonItem(
#   value: "C:/Absytree/src/text/language/lsp_types.nim",
#   context: (20, 0).Cursor.toJson,
# )

# list[].items.add HarpoonItem(
#   value: "C:/Absytree/config/keybindings_vim.nim",
#   context: (30, 0).Cursor.toJson,
# )

dumpState()

when defined(wasm):
  include absytree_runtime_impl
