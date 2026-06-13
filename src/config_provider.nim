import std/[json, options, tables, macros, genasts, sets, typetraits, strformat, strutils]
import misc/[util, event, custom_async, custom_logger, myjsonutils, jsonex, id, custom_unicode]
import service, lisp
import config_store
from scripting_api import LineNumbers

export config_store

include misc/dynlib_export

logCategory "config"

type
  ConfigLayerKind* = enum Unchanged, Extend, Override

  ConfigService* = ref object of Service
    onConfigChanged*: Event[void]
    base*: ConfigStore
    runtime*: ConfigStore

    storeGroups*: Table[string, seq[ConfigStore]]
    stores*: Table[string, ConfigStore]
    storesByName*: Table[string, ConfigStore]
    groups*: seq[string]

  Setting*[T] = ref object
    store*: ConfigStore
    cache*: Option[T]
    revision*: int
    key*: string
    defaultValue*: T

  SettingGroupDescription* = object
    settings*: seq[int]

  SettingDescription* = object
    fullName*: string
    prefix*: string
    name*: string
    typ*: string
    typeName*: string
    default*: string
    docs*: string
    noInit*: bool

  DiagnosticsLocation* = enum LineEnd = "line-end", Below = "below", LineEndOrBelow = "line-end-or-below"

  ToastStyle* = enum Minimal = "minimal", Box = "box"

func serviceName*(_: typedesc[ConfigService]): string = "ConfigService"

const defaultToJsonOptions = ToJsonOptions(enumMode: joptEnumString, jsonNodeMode: joptJsonNodeAsRef)

proc toJsonExHook*[T](a: Setting[T]): JsonNodeEx {.raises: [].} =
  let v = a.get()
  return v.toJsonEx(defaultToJsonOptions)

proc setting*(self: ConfigStore, key: string, T: typedesc, def: JsonNodeEx = nil): Setting[T] {.gcsafe.} =
  # if def != nil:
  #   echo &"setting '{key}' with def {def}"
  let def = try:
    if def != nil:
      when T is JsonNodeEx:
        def
      elif T is JsonNode:
        def.toJson()
      else:
        def.jsonTo(T)
    else:
      T.default
  except CatchableError:
    T.default

  return Setting[T](store: self, key: key, defaultValue: def)

{.push apprtl, gcsafe, raises: [].}
proc configServiceGetLanguageStore(self: ConfigService, languageId: string): ConfigStore
proc configServiceAddStore(self: ConfigService, name, filename: string, parent: ConfigStore = nil, settings: JsonNodeEx = newJexObject()): ConfigStore
proc configServiceRemoveStore(self: ConfigService, store: ConfigStore)
proc configServiceGetByPath(self: ConfigService, path: string): JsonNodeEx
proc configServiceGetStoreForPath(self: ConfigService, path: string): (ConfigStore, string)
proc configReconnectGroups(self: ConfigService)
proc configGetStoreForId(self: ConfigService, id: int): ConfigStore
proc configGetSettingDescription(self: ConfigService, key: string): Option[SettingDescription]
{.pop.}

proc getLanguageStore*(self: ConfigService, languageId: string): ConfigStore = configServiceGetLanguageStore(self, languageId)
proc addStore*(self: ConfigService, name, filename: string, parent: ConfigStore = nil, settings: JsonNodeEx = newJexObject()): ConfigStore = configServiceAddStore(self, name, filename, parent, settings)
proc removeStore*(self: ConfigService, store: ConfigStore) = configServiceRemoveStore(self, store)
proc getByPath*(self: ConfigService, path: string): JsonNodeEx = configServiceGetByPath(self, path)
proc getStoreForPath*(self: ConfigService, path: string): (ConfigStore, string) = configServiceGetStoreForPath(self, path)
proc reconnectGroups*(self: ConfigService) = configReconnectGroups(self)
proc getStoreForId*(self: ConfigService, id: int): ConfigStore = configGetStoreForId(self, id)
proc getSettingDescription*(self: ConfigService, key: string): Option[SettingDescription] = configGetSettingDescription(self, key)

proc get*[T](self: Setting[T], default: T): lent T =
  if self.cache.isSome and self.revision == self.store.revision:
    return self.cache.get
  self.cache = self.store.get(self.key, default).some
  self.revision = self.store.revision
  return self.cache.get

proc get*[T](self: Setting[T]): lent T =
  return self.get(self.defaultValue)

proc set*[T](self: Setting[T], value: T) =
  self.store.set(self.key, value)

proc get*[T](self: Setting[Option[T]], default: T): T =
  let v = self.get()
  if v.isSome:
    return v.get
  return default

proc getRegex*(self: Setting[RegexSetting], default: string = ""): string =
  let value = self.get().impl
  if value == nil:
    return default
  return value.decodeRegex(default)

proc getRegex*(self: Setting[Option[RegexSetting]]): Option[string] =
  let value = self.get()
  if value.isNone:
    return string.none
  return value.get.decodeRegex("").some

proc getRegex*(self: Setting[Option[RegexSetting]], default: string): string =
  let value = self.get()
  if value.isNone:
    return default
  return value.get.decodeRegex(default)

proc camelCaseToHyphenCase(str: string): string =
  for c in str:
    if c.isUpperAscii:
      result.add "-"
      result.add c.toLowerAscii
    else:
      result.add c

proc joinSettingKey*(a, b: string): string =
  if a.len > 0 and b.len > 0:
    return a & "." & b
  elif a.len > 0:
    return a
  else:
    return b

proc typeNameToJson*(T: typedesc): string =
  return $T

proc typeNameToJson*(T: typedesc[JsonNode]): string =
  return "any"

proc typeNameToJson*(T: typedesc[RegexSetting]): string =
  return "regex"

proc typeNameToJson*(T: typedesc[RuneSetSetting]): string =
  return "(string | string[])[]"

proc typeNameToJson*[K](T: typedesc[seq[K]]): string =
  let subTypeName = typeNameToJson(K)
  if subTypeName.find(" ") != -1 and not subTypeName.endsWith(")") and not subTypeName.endsWith("]") and not subTypeName.endsWith("}"):
    return "(" & subTypeName & ")[]"
  else:
    return subTypeName & "[]"

proc typeNameToJson*[K](T: typedesc[Option[K]]): string =
  return typeNameToJson(K) & " | null"

proc typeNameToJson*[K](T: typedesc[Table[string, K]]): string =
  return "{ [key: string]: " & typeNameToJson(K) & " }"

proc typeNameToJson*(T: typedesc[LineNumbers]): string =
  return "\"none\" | \"absolute\" | \"relative\""

proc typeNameToJson*(T: typedesc[DiagnosticsLocation]): string =
  return "\"line-end\" | \"below\" | \"line-end-or-below\""

proc typeNameToJson*(T: typedesc[ToastStyle]): string =
  return "\"minimal\" | \"box\""

proc declareSettingsImpl(name: NimNode, prefix: string, noInit: static[bool], body: NimNode): NimNode {.compileTime.} =
  let declare = ident"declare"
  let use = ident"use"
  let store = genSym(nskParam, "store")
  let prefixArg = genSym(nskParam, "prefix")
  let res = genSym(nskVar, "res")

  var typeNode = genAst(name):
    type name* = object
      x: int

  typeNode[0][2][2] = nnkRecList.newTree()

  var newNode = genAst(name, store, res, prefix = prefixArg, defaultPrefix = prefix):
    proc new*(_: typedesc[name], store: ConfigStore, prefix: string = defaultPrefix): name {.gcsafe.} =
      var res = name()
      # result.foo = store.setting("foo", int)

  template withPrefix(s: string): string =
    block:
      if prefix.len > 0:
        prefix & "." & s
      else:
        s

  var docs: NimNode = nil
  for node in body:
    if node.kind == nnkCommentStmt:
      docs = node
      continue

    if node.kind == nnkCommand and node[0] == declare:
      let name = node[1]
      let fullName = name.repr.camelCaseToHyphenCase.withPrefix()
      let settingName = name.repr.camelCaseToHyphenCase
      let typ = node[2]
      let default = node[3]

      var s = SettingDescription(name: settingName, prefix: prefix, fullName: fullName, typ: typ.repr, default: "null", noInit: noInit)


      if docs != nil:
        s.docs = docs.strVal

      typeNode[0][2][2].add nnkIdentDefs.newTree(name.postfix("*"), nnkBracketExpr.newTree(bindSym"Setting", typ), newEmptyNode())

      newNode[6].add block:
        if default.repr == "nil":
          genAst(fieldName = name, settingName, typ, store, res, prefixArg):
            res.fieldName = ({.gcsafe.}: store.setting(joinSettingKey(prefixArg, settingName), typ))
        else:
          genAst(fieldName = name, settingName, typ, store, res, prefixArg, default):
            res.fieldName = ({.gcsafe.}: store.setting(joinSettingKey(prefixArg, settingName), typ, when typeof(default) is JsonNodeEx: copy(default) else: default.toJsonEx(defaultToJsonOptions)))

      docs = nil
      continue

    if node.kind == nnkCommand and node[0] == use:
      let name = node[1]
      let fullName = name.repr.camelCaseToHyphenCase.withPrefix()
      let typ = node[2]

      typeNode[0][2][2].add nnkIdentDefs.newTree(name.postfix("*"), typ, newEmptyNode())

      let settingName = name.repr.camelCaseToHyphenCase
      newNode[6].add block:
        genAst(fieldName = name, typ, store, res, prefixArg, settingName):
          res.fieldName = typ.new(store, joinSettingKey(prefixArg, settingName))

      continue

    if node.kind == nnkIdent:
      discard

    error "Invalid setting, expected 'declare name, type, default'", node

  newNode[6].add block:
    genAst(res):
      return res

  result = nnkStmtList.newTree(typeNode, newNode)

macro declareSettings*(name: untyped, prefix: static string, body: untyped) =
  return declareSettingsImpl(name, prefix, false, body)

macro declareSettingsTemplate*(name: untyped, prefix: static string, body: untyped) =
  return declareSettingsImpl(name, prefix, true, body)

when implModule:
  import std/[algorithm, macrocache]
  import misc/expose
  import platform
  import dispatch_tables
  import default_settings

  {.push gcsafe.}
  {.push raises: [].}

  addBuiltinService(ConfigService)

  method init*(self: ConfigService): Future[Result[void, ref CatchableError]] {.async: (raises: []).} =
    log lvlInfo, &"ConfigService.init"
    # {.gcsafe.}:
      # for desc in getSettingDescriptions():
      #   self.settingDescriptions.add desc

    self.base = ConfigStore.new("base", "settings://base")
    fillDefaultSettings(self.base)
    self.runtime = ConfigStore.new("runtime", "settings://runtime")
    self.runtime.setParent(self.base)
    return ok()

  proc configGetSettingDescription(self: ConfigService, key: string): Option[SettingDescription] =
    return SettingDescription.none

  proc configServiceRemoveStore(self: ConfigService, store: ConfigStore) =
    store.setParent(nil)
    self.stores.del(store.filename)
    self.storesByName.del(store.name)

  proc configServiceAddStore(self: ConfigService, name, filename: string, parent: ConfigStore = nil, settings: JsonNodeEx = newJexObject()): ConfigStore =
    let parent = if parent != nil: parent else: self.runtime
    result = ConfigStore.new(name, filename, parent, settings)
    self.stores[filename] = result
    self.storesByName[name] = result

  proc configServiceGetLanguageStore(self: ConfigService, languageId: string): ConfigStore =
    let path = "languages/" & languageId
    if self.stores.contains(path):
      return self.stores[path]

    let prefix = "lang." & languageId
    let store = self.addStore(languageId, path, self.runtime)
    let v = store.parent.get(prefix)
    if v != nil:
      store.setSettings(v)
    store.parent.onConfigChanged.unsubscribe(store.parentChangedHandle)
    store.parentChangedHandle = store.parent.onConfigChanged.subscribe proc(key: string) =
      if key.startsWith(prefix) or key == "lang" or key == "":
        let v = store.parent.get(prefix)
        if v != nil:
          store.setSettings(v)
        else:
          store.setSettings(newJexObject())
      else:
        var val = store.settings
        var extend = val.extend
        for keyRaw in key.splitOpenArray('.'):
          if isNil(val) or val.kind != JObject:
            val = nil
            break
          val = val.fields.getOrDefault(keyRaw.p.toOpenArray(0, keyRaw.len - 1))
          if val != nil:
            extend = extend and val.extend

        if val == nil or extend:
          store.onConfigChanged.invoke(key)

    return store

  proc firstGroupConfigStore*(self: ConfigService): ConfigStore =
    for group in self.groups:
      if group notin self.storeGroups:
        continue
      let stores = self.storeGroups[group]
      if stores.len == 0:
        continue
      return stores[0]

    return nil

  proc lastGroupConfigStore*(self: ConfigService): ConfigStore =
    for i in countdown(self.groups.high, 0):
      let group = self.groups[i]
      if group notin self.storeGroups:
        continue
      let stores = self.storeGroups[group]
      if stores.len == 0:
        continue
      return stores[^1]

    return nil

  proc configReconnectGroups(self: ConfigService) =
    var lastGroup = self.groups[0]
    for i in 1..self.groups.high:
      let childGroup = self.groups[i]

      if childGroup notin self.storeGroups:
        continue

      if lastGroup in self.storeGroups:
        let child = self.storeGroups[childGroup][0]
        let parent = self.storeGroups[lastGroup][^1]
        child.setParent(parent)

      lastGroup = childGroup

    let first = self.firstGroupConfigStore()
    if first != nil:
      first.setParent(self.base)

      let last = self.lastGroupConfigStore()
      assert last != nil
      self.runtime.setParent(last)

    else:
      self.runtime.setParent(self.base)

  proc configGetStoreForId(self: ConfigService, id: int): ConfigStore =
    for store in self.runtime.parentStores:
      if store.id == id:
        return store

    return nil

  proc configServiceGetStoreForPath(self: ConfigService, path: string): (ConfigStore, string) =
    for store in self.runtime.parentStores:
      if path.startsWith(store.name):
        return (store, path[store.name.len..^1].strip(chars = {'/'}).replace("/", "."))

    for storeName in self.storesByName.keys:
      if path.startsWith(storeName & "/"):
        return (self.storesByName[storeName], path[storeName.len..^1].strip(chars = {'/'}).replace("/", "."))
      if path == storeName:
        return (self.storesByName[storeName], "")

    log lvlWarn, &"getStoreForPath '{path}' not found"
    return (nil, "")

  proc configServiceGetByPath(self: ConfigService, path: string): JsonNodeEx =
    let (store, key) = self.getStoreForPath(path)
    if store == nil:
      return nil
    return store.get(key)

  proc getByPath*(self: ConfigService, path: string, T: typedesc, defaultValue: T): T =
    let value = self.getByPath(path)
    if value != nil:
      try:
        return value.jsonTo(T)
      except Exception as e:
        let t = $T
        log lvlError, &"Failed to get setting as type {t}: {e.msg}\n{value.pretty}"
        return defaultValue
    else:
      return defaultValue

  proc getByPath*(self: ConfigService, path: string, T: typedesc): T {.inline.} =
    self.getByPath(path, T, T.default)

  ###########################################################################

  proc getConfigService(): Option[ConfigService] =
    {.gcsafe.}:
      if getServices().isNil: return ConfigService.none
      return getServices().getService(ConfigService)

  static:
    addInjector(ConfigService, getConfigService)

  proc logOptions*(self: ConfigService) {.expose("config").} =
    log lvlInfo, self.runtime.mergedSettings.pretty()

  proc setOption*(self: ConfigService, option: string, value: JsonNode, override: bool = true) {.expose("config").} =
    if self.isNil:
      return

    self.runtime.set(option, value.toJsonEx(defaultToJsonOptions))
    self.onConfigChanged.invoke()
    self.services.getServiceChecked(PlatformService).platform.requestRender(true)

  proc cycleOption*(self: ConfigService, path: string, values: JsonNode) {.expose("config").} =
    if self.isNil:
      return

    let current = self.runtime.get(path, newJNull())
    if values.kind == JArray:
      for i, option in values.elems:
        if option == current:
          let nextIndex = (i + 1) mod values.elems.len
          let value = values.elems[nextIndex]
          self.runtime.set(path, value.toJsonEx(defaultToJsonOptions))
          self.onConfigChanged.invoke()
          self.services.getServiceChecked(PlatformService).platform.requestRender(true)
          return
      if values.elems.len > 0:
        let value = values.elems[0]
        self.runtime.set(path, value.toJsonEx(defaultToJsonOptions))
        self.onConfigChanged.invoke()
        self.services.getServiceChecked(PlatformService).platform.requestRender(true)

  proc getOptionJson*(self: ConfigService, path: string, default: JsonNode = newJNull()): JsonNode {.expose("editor").} =
    return self.runtime.get(path, default)

  proc getFlag*(self: ConfigService, flag: string, default: bool = false): bool {.expose("config").} =
    return self.runtime.get(flag, bool, default)

  proc setFlag*(self: ConfigService, flag: string, value: bool) {.expose("config").} =
    self.runtime.set(flag, value)

  proc toggleFlag*(self: ConfigService, flag: string) {.expose("config").} =
    let newValue = not self.getFlag(flag)
    log lvlInfo, fmt"toggleFlag '{flag}' -> {newValue}"
    self.setFlag(flag, newValue)

  addGlobalDispatchTable "config", genDispatchTable("config")

  {.pop.} # raises: []
  {.pop.} # gcsafe

declareSettings BackgroundSettings, "":
  ## If true the background is transparent.
  declare transparent, bool, false

  ## How much to change the brightness for inactive views.
  declare inactiveBrightnessChange, float, -0.025

declareSettings ToastSettings, "":
  ## Animate toast positions
  declare style, ToastStyle, ToastStyle.Minimal

  ## How long toasts are displayed for, in milliseconds.
  declare duration, int, 8000

  ## Animate toast positions
  declare animation, bool, true

  ## Max number of toast to show at a time
  declare max, int, 5

declareSettings OpenSessionSettings, "":
  ## If true then Nev will detect if it's running inside a multiplexer like tmux, zellij or wezterm (by using environment variables)
  ## and if so opening a session will use the command `editor.open-session.tmux` or `editor.open-session.zellij` or `editor.open-session.wezterm`
  declare useMultiplexer, bool, true

  ## Command to use when opening a session in a new window.
  declare command, Option[string], nil

  ## Command arguments to use when opening a session in a new window.
  declare args, Option[seq[JsonNodeEx]], nil

declareSettings UiSettings, "ui":
  use background, BackgroundSettings

  use toast, ToastSettings

  ## VFS path of the theme.
  declare theme, string, "app://themes/gruvbox-dark.json"

  ## Full path to regular font file.
  declare fontFamily, string, "app://fonts/DejaVuSansMono.ttf"

  ## Full path to bold font file.
  declare fontFamilyBold, string, "app://fonts/DejaVuSansMono-Bold.ttf"

  ## Full path to italic font file.
  declare fontFamilyItalic, string, "app://fonts/DejaVuSansMono-Oblique.ttf"

  ## Full path to bold italic font file.
  declare fontFamilyBoldItalic, string, "app://fonts/DejaVuSansMono-BoldOblique.ttf"

  ## After how many milliseconds the which key window opens.
  declare whichKeyDelay, int, 250

  ## Show which key window when holding down modifiers.
  declare whichKeyShowWhenMod, bool, false

  ## If true then the window showing next possible inputs will be displayed even when no keybinding is in progress (i.e. it will always be shown).
  declare whichKeyNoProgress, bool, false

  ## How many rows tall the window showing next possible inputs should be.
  declare whichKeyHeight, int, 6

  ## How many rows tall the window showing next possible inputs should be when showing in a popup.
  declare popupWhichKeyHeight, int, 5

  ## Maximum number of views (files or other UIs) which can be shown.
  declare maxViews, int, 2

  ## Enable syntax highlighting.
  declare syntaxHighlighting, bool, true

  ## Enable highlighting parentheses, brackets etc in different colors. Uses "rainbow0", "rainbow1" etc theme keys.
  declare rainbowParentheses, bool, false

  ## Enable indent guides to show the indentation of the current line.
  declare indentGuide, bool, true

  ## Character to use when rendering whitespace. If this is the empty string or not set then spaces are not rendered.
  declare whitespaceChar, string, "·"

  ## Color of rendered whitespace. Can be a theme key or hex color (e.g #ff00ff).
  declare whitespaceColor, string, "comment"

  ## How many pixels (or rows in the terminal) to scroll per scroll wheel tick.
  declare scrollSpeed, float, 50.0

  ## Enable smooth scrolling.
  declare smoothScroll, bool, true

  ## How fast smooth scrolling interpolates.
  declare smoothScrollSpeed, float, 25.0

  ## Percentage of screen height at which the smooth scroll offset will be snapped to the target location.
  ## E.g. if this is 0.5, then if the smooth scroll offset if further from the target scroll offset than 50% of the
  ## screen height then the smooth scroll offset will instantly jump to the target scroll offset (-50% of the screen height).
  ## This means that the smooth scrolling will not take time proportional to the scroll distance for jumps bigger than
  ## the screen height.
  declare smoothScrollSnapThreshold, float, 0.5

  ## How fast to interpolate the cursor trail position when moving the cursor. Higher means faster.
  declare cursorTrailSpeed, float, 100.0

  ## How long the cursor trail is. Set to 0 to disable cursor trail.
  declare cursorTrailLength, int, 2

  ## Enable vertical sync to prevent screen tearing.
  declare vsync, bool, true

  ## How line numbers should be displayed.
  declare lineNumbers, LineNumbers, LineNumbers.Absolute

  ## Where diagnostics are displayed relative to their source line.
  ## "below" renders them on a separate line below.
  ## "line-end" renders the first diagnostic inline at the end of the line.
  ## "line-end-or-below" renders below on the cursor line, at line-end elsewhere (default).
  declare diagnosticsLocation, DiagnosticsLocation, DiagnosticsLocation.LineEnd

  # Defines the way views are layed out.
  # declare layout, JsonNodeEx, newJexObject()

  ## Width of tab layout headers in characters
  declare tabHeaderWidth, int, 30

  ## When true then tab layouts don't render a tab bar when they only have one tab.
  declare hideTabBarWhenSingle, bool, false

  # ## How long the cursor trail is. Set to 0 to disable cursor trail.
  # declare inclusiveSelection, int, 2

  ## Configures what to show in the status line.
  declare statusLine, seq[JsonNodeEx], @[newJexString"mode", newJexString"layout", newJexString"vcs.status", newJexString"session"]

  ## Whether a scrollbar is shown.
  declare scrollBar, bool, true

  ## Whether changes within a line should be highlighted in the diff view
  declare highlightInlineChanges, bool, true

declareSettings GeneralSettings, "editor":
  use openSession, OpenSessionSettings

  ## How often the editor will check for unused documents and close them, in seconds.
  declare closeUnusedDocumentsTimer, int, 10

  ## If true the editor prints memory usage statistics when quitting.
  declare printStatisticsOnShutdown, bool, false

  ## Max number of search results returned by global text based search.
  declare maxSearchResults, int, 1000

  ## Max length of each individual search result (search results are cut off after this value).
  declare maxSearchResultDisplayLen, int, 1000

  ## If true then the app mode event handler (if the app mode is not "") will be on top of the event handler stack,
  ## otherwise it will be at the bottom (but still above the "editor" event handler.
  declare customModeOnTop, bool, true

  ## After how many milliseconds of no input the input history is cleared.
  declare clearInputHistoryDelay, int, 3000

  ## After how many milliseconds of no input a pending input gets inserted as text, if you bind a key
  ## which inserts text in e.g. a multi key keybinding aswell.
  ## Say you bind `jj` to exit insert mode, then if you press `j` once and wait for this delay then it will
  ## insert `j` into the document, but if you press `j` again it will will exit insert mode instead.
  ## If you press another key like `k` before the time ends it will immediately insert the `j` and the `k`.
  declare insertInputDelay, int, 150

  ## Whether the editor shows a history of the last few pressed buttons in the status bar.
  declare recordInputHistory, bool, false

  ## Watch the theme directory for changes to the theme.
  declare watchTheme, bool, true

  ## Watch the config files in the app directory and automatically reload them when they change.
  declare watchAppConfig, bool, true

  ## Watch the config files in the user directory and automatically reload them when they change.
  declare watchUserConfig, bool, true

  ## Watch the config files in the workspace directory and automatically reload them when they change.
  declare watchWorkspaceConfig, bool, true

  ## If true then the editor will keep a history of opened sessions in data://sessions.json,
  ## which enables features like opening a recent session or opening the last session.
  declare keepSessionHistory, bool, true

  ## If true then you will be prompted to confirm quitting even when no unsaved changes exist.
  declare promptBeforeQuit, bool, false

  ## List of input modes which are always active (at the lowest priority).
  declare baseModes, seq[string], @["editor"]

  ## Global mode to apply while the command line is open.
  declare commandLineModeHigh, string, "command-line-high"

  ## Global mode to apply while the command line is open.
  declare commandLineModeLow, string, "command-line-low"

  ## Global mode to apply while the command line is open showing a command result.
  declare commandLineResultModeHigh, string, "command-line-result-high"

  ## Global mode to apply while the command line is open showing a command result.
  declare commandLineResultModeLow, string, "command-line-result-low"

  ## Global mode to apply while the command line is open showing a command result.
  declare treesitterWasmDownloadUrl, string, "https://github.com/Nimaoth/tree-sitter-wasm-binaries/releases/download/v0.3/{language}.tar.gz"

declareSettings DebugSettings, "debug":
  ## Log how long it takes to generate the render commands for a text editor.
  declare logTextRenderTime, bool, false

  ## GUI only: Highlight text chunks
  declare drawTextChunks, bool, false

  ## Write logs to an internal document which can be opened using the `logs` command.
  declare logToInternalDocument, bool, false

declareSettingsTemplate TreesitterSettings, "text.treesitter":
  ## Enable parsing code into ASTs using treesitter. Also requires a treesitter parser for a specific language.
  declare enable, bool, true

  ## Override the path to the treesitter parser (.dll/.so/.wasm). By default
  declare path, Option[string], nil

  ## Override the language name used for choosing the treesitter parser. If not set then the documents language id is used.
  declare language, Option[string], nil

  ## Path relative to the repository root where queries are located. If not set then the editor will look for the queries.
  declare queries, Option[string], nil

  ## Path relative to the repository root where queries are located. If not set then the editor will look for the queries.
  declare repository, Option[string], nil
