import std/[strformat, options, tables, sets, strutils]
import misc/[util, custom_logger]
import platform
import view, document_editor, layout/layout, service
import types_impl, debugger, dap_client

from nuigi import UiBuilder, UiBackendType, UiStyleIndex, UiTextStyleIndex,
  UiNodeStorageData, text, textStyleIndex, fit, fitY, node, fillX, fillY,
  fillBackground, styleIndex,
  padding, gap, layoutVertical, layoutHorizontal, currentNode, currentNodeIndex,
  nodeStorage, nodeStorageGet, nodeStorageParent,
  wasClicked, wasHovered, wrapText
import nuigi/widgets/dynamic_virtuallist
import nuigi/widgets/tree_table
from nuigi/widgets import tableColumnProportional
import nuigi/debug/profiler
from std/unicode import runeLen, runeSubStr

# Mark this entire file as used, otherwise we get warnings when importing it but only calling a method
{.used.}

logCategory "widget_builder_debugger"

proc truncDebuggerText*(s: string, maxRunes: int): string {.gcsafe, raises: [].} =
  ## Truncates to maxRunes runes (never splitting UTF-8) with an ellipsis.
  try:
    if s.runeLen <= maxRunes:
      return s
    return s.runeSubStr(0, maxRunes) & "…"
  except:
    result = s

template debuggerChrome(nui: var UiBuilder, view: View, rootName,
    titleText: string, body: untyped) =
  ## Shared Panel root + Header bar chrome (mirrors renderView in widget_library).
  block:
    let panelStyle = if view.active: UiStyleIndexPanelActive else: UiStyleIndexPanel
    let headerStyle = if view.active: UiStyleIndexHeaderActive else: UiStyleIndexHeader
    nui.layoutVertical(rootName):
      discard nui.fillX().fillY().fillBackground().styleIndex(
        panelStyle).backendPadding(4).backendGap(4)
      try:
        if nui.wasClicked(includeChildren = true):
          getServiceChecked(LayoutService).tryActivateView(view)
      except:
        discard
      nui.layoutHorizontal(rootName & "-header"):
        discard nui.fillX().fitY().fillBackground().styleIndex(
          headerStyle).backendPadding(4).backendGap(4)
        nui.node:
          discard nui.fit().textStyleIndex(
            int(UiStyleIndexHeaderText)).text(titleText)
      body

template debuggerEmpty(nui: var UiBuilder, msg: string) =
  nui.node:
    discard nui.fit().textStyleIndex(
      int(UiStyleIndexDefaultText)).text(msg)

type DebuggerStacktraceNuiStorage = ref object of UiNodeStorageData
  view: StacktraceView
  debugger: Debugger
  listStorage: UiDynamicVirtualListStorage
  lastSelected: int = -1

proc getOrCreateDebuggerStacktraceNuiStorage(
    b: var UiBuilder, node: auto): DebuggerStacktraceNuiStorage =
  let existing = b.nodeStorageGet(node)
  if existing != nil:
    return cast[DebuggerStacktraceNuiStorage](existing)
  var storage = DebuggerStacktraceNuiStorage()
  b.nodeStorage(node, storage)
  storage

proc debuggerLineHeight(nui: var UiBuilder): float32 {.gcsafe, raises: [].} =
  ## Single-line row height hint for the debugger lists.
  try:
    if nui.backendType == UiBackendType.Terminal:
      return 1.0'f32
    let platform = getServiceChecked(PlatformService).platform
    if platform != nil:
      return max(1.0'f32, platform.lineHeight.float32)
  except:
    discard
  return 18.0'f32

proc buildStacktraceRowNui(b: var UiBuilder, itemIndex: int,
    userData: int) {.nimcall, gcsafe, raises: [].} =
  if userData < 0 or userData >= b.frame.nodes.len:
    return
  let existing = b.nodeStorageGet(b.frame.nodes[userData].addr)
  if existing == nil or not (existing of DebuggerStacktraceNuiStorage):
    return
  let storage = cast[DebuggerStacktraceNuiStorage](existing)
  if storage.debugger == nil or storage.view == nil or itemIndex < 0:
    return
  try:
    # Read the row directly from the stack trace (no per-frame snapshot copy).
    if storage.debugger.currentThread().getSome(t):
      if storage.debugger.getStackTrace(t.id).getSome(stack):
        if itemIndex > stack[].stackFrames.high:
          return
        let frame = stack[].stackFrames[itemIndex]
        var rowText = &"{frame.name}:{frame.line}"
        if frame.source.getSome(source):
          if source.name.isSome:
            rowText.add &" - {source.name.get}"
          elif source.path.isSome:
            rowText.add &" - {source.path.get}"
        let selected = itemIndex == storage.debugger.currentFrameIndex
        discard b.fillX().fitY().fillBackground().styleIndex(if selected or
            b.wasHovered(includeChildren = true):
          UiStyleIndexMenuItemHover
        else:
          UiStyleIndexMenuItem)
        b.node:
          discard b.fit().textStyleIndex(int(if selected:
            UiStyleIndexMenuItemHoverText
          else:
            UiStyleIndexMenuItemText)).text(rowText)
        if b.wasClicked(includeChildren = true):
          storage.debugger.selectStackFrame(itemIndex)
          storage.view.markDirty()
  except:
    discard

proc createStackTraceUINui*(self: StacktraceView, nui: var UiBuilder,
    debugger: Debugger) {.gcsafe, raises: [].} =
  {.cast(gcsafe).}:
    try:
      self.resetDirty()
      var title = "Stack"
      var frameCount = 0
      try:
        if debugger.currentThread().getSome(t):
          title = &"Stack - Thread {t.id} {t.name}"
          if debugger.getStackTrace(t.id).getSome(stack):
            frameCount = stack[].stackFrames.len
      except:
        discard
      debuggerChrome(nui, self, "debugger-stacktrace", title):
        nui.node("debugger-st-body"):
          discard nui.fillX().fillY()
          nui.nodeStorageParent()
          let bodyIndex = nui.currentNodeIndex
          let storage = nui.getOrCreateDebuggerStacktraceNuiStorage(
            nui.currentNode)
          storage.view = self
          storage.debugger = debugger
          if frameCount == 0:
            debuggerEmpty(nui, "No stack trace")
          else:
            storage.listStorage = nui.dynamicVirtualList(frameCount,
              debuggerLineHeight(nui), buildStacktraceRowNui, bodyIndex)
            if storage.listStorage != nil and
                storage.lastSelected != debugger.currentFrameIndex and
                storage.listStorage.ensureItemVisible(
                  debugger.currentFrameIndex,
                  storage.listStorage.viewportHeight, 0.0'f32):
              storage.lastSelected = debugger.currentFrameIndex
    except:
      discard

type DebuggerThreadsNuiStorage = ref object of UiNodeStorageData
  view: ThreadsView
  debugger: Debugger
  listStorage: UiDynamicVirtualListStorage
  lastSelected: int = -1

proc getOrCreateDebuggerThreadsNuiStorage(
    b: var UiBuilder, node: auto): DebuggerThreadsNuiStorage =
  let existing = b.nodeStorageGet(node)
  if existing != nil:
    return cast[DebuggerThreadsNuiStorage](existing)
  var storage = DebuggerThreadsNuiStorage()
  b.nodeStorage(node, storage)
  storage

proc buildThreadsRowNui(b: var UiBuilder, itemIndex: int,
    userData: int) {.nimcall, gcsafe, raises: [].} =
  if userData < 0 or userData >= b.frame.nodes.len:
    return
  let existing = b.nodeStorageGet(b.frame.nodes[userData].addr)
  if existing == nil or not (existing of DebuggerThreadsNuiStorage):
    return
  let storage = cast[DebuggerThreadsNuiStorage](existing)
  if storage.debugger == nil or storage.view == nil or itemIndex < 0:
    return
  try:
    # Read the row directly from the thread list (lent, no copy).
    let threads {.cursor.} = storage.debugger.getThreads()
    if itemIndex > threads.high:
      return
    let rowText = &"{threads[itemIndex].id} - {threads[itemIndex].name}"
    let selected = itemIndex == storage.debugger.currentThreadIndex
    discard b.fillX().fitY().fillBackground().styleIndex(if selected or
        b.wasHovered(includeChildren = true):
      UiStyleIndexMenuItemHover
    else:
      UiStyleIndexMenuItem)
    b.node:
      discard b.fit().textStyleIndex(int(if selected:
        UiStyleIndexMenuItemHoverText
      else:
        UiStyleIndexMenuItemText)).text(rowText)
    if b.wasClicked(includeChildren = true):
      storage.debugger.selectThread(itemIndex)
      storage.view.markDirty()
  except:
    discard

proc createThreadsUINui*(self: ThreadsView, nui: var UiBuilder,
    debugger: Debugger) {.gcsafe, raises: [].} =
  {.cast(gcsafe).}:
    try:
      self.resetDirty()
      var threadCount = 0
      try:
        threadCount = debugger.getThreads().len
      except:
        discard
      debuggerChrome(nui, self, "debugger-threads", "Threads"):
        nui.node("debugger-th-body"):
          discard nui.fillX().fillY()
          nui.nodeStorageParent()
          let bodyIndex = nui.currentNodeIndex
          let storage = nui.getOrCreateDebuggerThreadsNuiStorage(
            nui.currentNode)
          storage.view = self
          storage.debugger = debugger
          if threadCount == 0:
            debuggerEmpty(nui, "No threads")
          else:
            storage.listStorage = nui.dynamicVirtualList(threadCount,
              debuggerLineHeight(nui), buildThreadsRowNui, bodyIndex)
            if storage.listStorage != nil and
                storage.lastSelected != debugger.currentThreadIndex and
                storage.listStorage.ensureItemVisible(
                  debugger.currentThreadIndex,
                  storage.listStorage.viewportHeight, 0.0'f32):
              storage.lastSelected = debugger.currentThreadIndex
    except:
      discard

# Variables tree table: DebuggerVariablesCursor navigates a DebuggerVarCache
# (cf. file_explorer's VirtualFileSystemCursorCache). Every cursor operation is
# a single hashtable lookup: listings are copied out of the debugger tables
# into per-key nodes, and row display data rides along in parent-linked
# locations, so rendering a row needs no lookup at all. Index-based keys stay
# valid across DAP refetches; copies are dropped wholesale whenever the
# context or table version changes. Expansion and keyboard navigation are owned
# entirely by the tree widget. Locations are immutable once published (never
# mutated in place), so sharing them between cloned cursors is safe.

proc copyVarChildren(vars: Variables): seq[DebuggerVarChild] {.gcsafe, raises: [].} =
  ## Copies one variables listing into display-ready children (first value
  ## line, truncated like the old precalculated rows).
  try:
    prof("copyVarChildren")
    result = newSeqOfCap[DebuggerVarChild](vars.variables.len)
    for va in vars.variables:
      let firstLine =
        try:
          if va.value.len == 0: ""
          else: va.value.splitLines()[0]
        except: va.value
      result.add DebuggerVarChild(name: va.name, typ: va.`type`.get(""),
        value: truncDebuggerText(firstLine, 160),
        childRef: va.variablesReference)
  except:
    result = @[]

proc fillVarRoot(cache: DebuggerVarCache) {.gcsafe, raises: [].} =
  ## (Re)builds the root scopes listing synchronously — scopes always live in
  ## memory, so this never needs the network.
  try:
    prof("fillVarRoot")
    if cache == nil or cache.debugger == nil:
      return
    var children: seq[DebuggerVarChild] = @[]
    try:
      if cache.debugger.currentScopes().getSome(scopes):
        children = newSeqOfCap[DebuggerVarChild](scopes[].scopes.len)
        for s in scopes[].scopes:
          children.add DebuggerVarChild(name: s.name, typ: "", value: "",
            childRef: s.variablesReference)
    except:
      discard
    cache.nodes[DebuggerVarRootKey] = DebuggerVarNode(
      childRef: 0.VariablesReference, fetched: true, children: children)
  except:
    discard

proc beginVarFrame(view: VariablesView,
    debugger: Debugger): DebuggerVarCache {.gcsafe, raises: [].} =
  ## Call once per render: validates the cache against the current context and
  ## table version (dropping stale listings), and ensures the root scopes
  ## listing. Returns nil when there is nothing to show.
  try:
    prof("beginVarFrame")
    if view == nil or debugger == nil:
      return nil
    if view.varCache == nil:
      view.varCache = DebuggerVarCache(debugger: debugger, view: view)
    result = view.varCache
    result.debugger = debugger
    result.view = view
    let ids = debugger.currentVariablesContext().getOr:
      result.valid = false
      return nil
    if not result.valid or result.ids != ids or
        result.version != debugger.varCacheVersion:
      result.nodes.clear()
      result.ids = ids
      result.version = debugger.varCacheVersion
      result.valid = true
      result.fillVarRoot()
    return result
  except:
    return nil

proc varNode(cache: DebuggerVarCache,
    loc: DebuggerVarLocation): ptr DebuggerVarNode {.gcsafe, raises: [].} =
  ## The single-lookup accessor for a location's listing. Fills synchronously
  ## from the debugger tables when the data is already there, and triggers a
  ## guarded DAP fetch otherwise (file_explorer cache-miss pattern: empty for
  ## this frame, view marked dirty on arrival).
  try:
    prof("varNode")
    if cache == nil or loc == nil or cache.debugger == nil or
        cache.view == nil or not cache.valid:
      return nil
    if not cache.nodes.contains(loc.key):
      if loc.key == DebuggerVarRootKey:
        cache.fillVarRoot()
      else:
        var node = DebuggerVarNode(childRef: loc.container, fetched: false)
        if loc.container != 0.VariablesReference:
          let dbg = cache.debugger
          if dbg.variables.contains(cache.ids & loc.container):
            node.children = copyVarChildren(
              dbg.variables[cache.ids & loc.container])
            node.fetched = true
          else:
            cache.view.requestVariableChildren(dbg, cache.ids, loc.container)
        else:
          node.fetched = true
        cache.nodes[loc.key] = node
    result = addr cache.nodes.mgetOrPut(loc.key, DebuggerVarNode())
    if not result.fetched and loc.container != 0.VariablesReference:
      cache.view.requestVariableChildren(cache.debugger, cache.ids,
        loc.container)
    return result
  except:
    return nil

proc applyVarLocation(c: DebuggerVariablesCursor,
    loc: DebuggerVarLocation) {.gcsafe, raises: [].} =
  try:
    prof("applyVarLocation")
    c.location = loc
    if loc == nil:
      c.fieldName = ""
      c.path = @[]
      c.index = 0
      return
    c.fieldName = loc.name
    c.path = loc.path
    c.index = loc.index
  except:
    discard

proc cursorAtVarLocation(c: DebuggerVariablesCursor,
    loc: DebuggerVarLocation): DebuggerVariablesCursor {.gcsafe, raises: [].} =
  ## Fresh cursor sharing the cache and location (clone semantics).
  try:
    if c == nil or c.cache == nil:
      return nil
    result = DebuggerVariablesCursor(cache: c.cache)
    result.applyVarLocation(loc)
  except:
    result = nil

proc childVarPath(parent: DebuggerVarLocation, index: int): seq[int] {.gcsafe, raises: [].} =
  ## Fresh index path for a child (navigation-only copy, like file_explorer's
  ## pathWithIndex).
  try:
    if parent == nil:
      return @[index]
    result = newSeq[int](parent.path.len + 1)
    for i in 0 ..< parent.path.len:
      result[i] = parent.path[i]
    result[^1] = index
  except:
    result = @[]

proc listedVarChild(c: DebuggerVariablesCursor, parent: DebuggerVarLocation,
    child: DebuggerVarChild, index: int): DebuggerVarLocation {.gcsafe, raises: [].} =
  ## Builds a child location from already-listed parent data — no lookups.
  try:
    prof("listedVarChild")
    if c == nil or parent == nil:
      return nil
    result = DebuggerVarLocation(
      parent: parent,
      key: parent.key & "/" & $index,
      scopeIdx: if parent.scopeIdx < 0: index else: parent.scopeIdx,
      index: index,
      path: childVarPath(parent, index),
      name: child.name,
      typ: child.typ,
      value: child.value,
      container: child.childRef)
  except:
    result = nil

proc locationForVarPath(cache: DebuggerVarCache,
    path: seq[int]): DebuggerVarLocation {.gcsafe, raises: [].} =
  ## Rebuilds a location top-down (used only by updatePath/replacePathPrefix,
  ## which the tree calls rarely when rebasing moved rows).
  try:
    prof("locationForVarPath")
    if cache == nil:
      return nil
    var loc = DebuggerVarLocation(key: DebuggerVarRootKey, scopeIdx: -1,
      index: 0, path: @[], name: "Variables",
      container: 0.VariablesReference)
    if path.len == 0:
      return loc
    for depthIdx in 0 ..< path.len:
      let node = cache.varNode(loc)
      if node == nil:
        return nil
      let idx = path[depthIdx]
      if idx < 0 or idx >= node.children.len:
        return nil
      let child = node.children[idx]
      var childPath = newSeq[int](loc.path.len + 1)
      for i in 0 ..< loc.path.len:
        childPath[i] = loc.path[i]
      childPath[^1] = idx
      loc = DebuggerVarLocation(parent: loc, key: loc.key & "/" & $idx,
        scopeIdx: if loc.scopeIdx < 0: idx else: loc.scopeIdx,
        index: idx, path: childPath, name: child.name, typ: child.typ,
        value: child.value, container: child.childRef)
    return loc
  except:
    return nil

method clone*(c: DebuggerVariablesCursor): TreeCursor {.gcsafe, raises: [].} =
  try:
    prof("clone")
    return c.cursorAtVarLocation(c.location)
  except:
    return nil

method cursorKey*(c: DebuggerVariablesCursor): string {.gcsafe, raises: [].} =
  try:
    prof("cursorKey")
    if c.location == nil:
      return DebuggerVarRootKey
    return c.location.key
  except:
    return DebuggerVarRootKey

method childCount*(c: DebuggerVariablesCursor): int {.gcsafe, raises: [].} =
  try:
    prof("childCount")
    if c.cache == nil or c.location == nil:
      return 0
    let node = c.cache.varNode(c.location)
    if node == nil:
      return 0
    return node.children.len
  except:
    return 0

method enterChild*(c: DebuggerVariablesCursor): bool {.gcsafe, raises: [].} =
  try:
    prof("enterChild")
    if c.cache == nil or c.location == nil:
      return false
    let node = c.cache.varNode(c.location)
    if node == nil or node.children.len == 0:
      return false
    let childLoc = c.listedVarChild(c.location, node.children[0], 0)
    if childLoc == nil:
      return false
    c.applyVarLocation(childLoc)
    return true
  except:
    return false

method exitChild*(c: DebuggerVariablesCursor): bool {.gcsafe, raises: [].} =
  try:
    prof("exitChild")
    if c.location == nil or c.location.parent == nil:
      return false
    c.applyVarLocation(c.location.parent)
    return true
  except:
    return false

proc moveVarSibling(c: DebuggerVariablesCursor,
    count: int): bool {.gcsafe, raises: [].} =
  try:
    prof("moveVarSibling")
    if c.cache == nil or c.location == nil or c.location.parent == nil:
      return false
    let parent = c.location.parent
    let node = c.cache.varNode(parent)
    if node == nil:
      return false
    let target = c.location.index + count
    if target < 0 or target >= node.children.len:
      return false
    let childLoc = c.listedVarChild(parent, node.children[target], target)
    if childLoc == nil:
      return false
    c.applyVarLocation(childLoc)
    return true
  except:
    return false

method moveNext*(c: DebuggerVariablesCursor, count: int = 1): bool {.gcsafe, raises: [].} =
  try:
    return c.moveVarSibling(count)
  except:
    return false

method movePrev*(c: DebuggerVariablesCursor, count: int = 1): bool {.gcsafe, raises: [].} =
  try:
    return c.moveVarSibling(-count)
  except:
    return false

method updatePath*(c: DebuggerVariablesCursor, path: seq[int]) {.gcsafe, raises: [].} =
  try:
    prof("updatePath")
    if c.cache == nil:
      return
    let loc = locationForVarPath(c.cache, path)
    if loc != nil:
      c.applyVarLocation(loc)
  except:
    discard

method replacePathPrefix*(c: DebuggerVariablesCursor, oldPrefixLen: int,
    newPrefix: seq[int]) {.gcsafe, raises: [].} =
  try:
    prof("replacePathPrefix")
    if c.cache == nil or c.location == nil:
      return
    let oldPath = c.location.path
    var newPath: seq[int]
    if oldPrefixLen == newPrefix.len:
      newPath = newSeq[int](oldPath.len)
      for i in 0 ..< oldPath.len:
        newPath[i] = if i < newPrefix.len: newPrefix[i] else: oldPath[i]
    else:
      let suffixLen = max(0, oldPath.len - oldPrefixLen)
      newPath = newSeq[int](newPrefix.len + suffixLen)
      for i in 0 ..< newPrefix.len:
        newPath[i] = newPrefix[i]
      for i in 0 ..< suffixLen:
        newPath[newPrefix.len + i] = oldPath[oldPrefixLen + i]
    let loc = locationForVarPath(c.cache, newPath)
    if loc != nil:
      c.applyVarLocation(loc)
  except:
    discard

method resolveChild*(c: DebuggerVariablesCursor,
    child: TreeCursor): TreeCursor {.gcsafe, raises: [].} =
  try:
    prof("resolveChild")
    if c.cache == nil or c.location == nil or child == nil or
        not (child of DebuggerVariablesCursor):
      return nil
    let e = DebuggerVariablesCursor(child)
    if e.location == nil or e.location.parent == nil:
      return nil
    if e.location.parent.key != c.location.key or e.location.index < 0:
      return nil
    let node = c.cache.varNode(c.location)
    if node == nil or e.location.index >= node.children.len:
      return nil
    let childLoc = c.listedVarChild(c.location,
      node.children[e.location.index], e.location.index)
    if childLoc == nil:
      return nil
    var fresh = DebuggerVariablesCursor(cache: c.cache)
    fresh.applyVarLocation(childLoc)
    result = fresh
  except:
    result = nil

proc toVariableCursor(c: DebuggerVariablesCursor): Option[VariableCursor] {.gcsafe, raises: [].} =
  ## Best-effort mapping back to the selection model via the parent chain —
  ## pointer hops only, no table lookups.
  try:
    prof("toVariableCursor")
    if c.location == nil or c.location.scopeIdx < 0:
      return VariableCursor.none
    var pairs = newSeq[tuple[index: int, varRef: VariablesReference]]()
    var cur = c.location
    while cur.parent != nil and cur.parent.parent != nil:
      pairs.add((cur.index, cur.parent.container))
      cur = cur.parent
    for i in 0 ..< pairs.len div 2:
      swap(pairs[i], pairs[pairs.high - i])
    return VariableCursor(scope: c.location.scopeIdx, path: pairs).some
  except:
    return VariableCursor.none

proc renderDebuggerVariablesRow(b: var UiBuilder, cursor: TreeCursor,
    index: int) {.nimcall, gcsafe, raises: [].} =
  ## Draws one row purely from its location — no table lookups. Uncached
  ## parents already triggered their fetch while the tree walked here.
  discard index
  try:
    prof("renderDebuggerVariablesRow")
    if cursor == nil or not (cursor of DebuggerVariablesCursor):
      return
    let c = DebuggerVariablesCursor(cursor)
    if c.cache == nil or c.cache.view == nil or c.location == nil or
        c.location.scopeIdx < 0:
      return
    let view = c.cache.view
    let loc = c.location
    var selected = false
    try:
      if view.variablesCursor.scope == loc.scopeIdx:
        selected = view.variablesCursor.variableCursorIndexPath() == loc.path
    except:
      discard
    # Background only for the selected row; the tree widget itself owns hover,
    # focus, chevrons and indentation guides.
    if selected:
      discard b.fillBackground().styleIndex(UiStyleIndexMenuItemHover)
    else:
      discard b.styleIndex(UiStyleIndexMenuItem)
    let rowTextStyle = int(if selected:
      UiStyleIndexMenuItemHoverText
    else:
      UiStyleIndexMenuItemText)
    b.node:
      discard b.fit().textStyleIndex(rowTextStyle).text(loc.name)
    if b.wasClicked(includeChildren = true):
      let sel = c.toVariableCursor()
      if sel.isSome:
        view.variablesCursor = sel.get()
        view.markDirty()
    b.node:
      discard b.fit().textStyleIndex(rowTextStyle).text(loc.typ)
    b.node:
      discard b.fit().textStyleIndex(rowTextStyle).text(loc.value)
  except:
    discard

# NUI-GAP vs the removed legacy renderer (custom render-command tree): no
# multiline values, no valueChanged background, no filter, no evaluation row,
# no drag-resize/detach, no SizeToContent modes; navigation (including the
# keyboard) is owned entirely by the tree widget (see §25).
proc createVariablesUINui*(self: VariablesView, nui: var UiBuilder,
    debugger: Debugger) {.gcsafe, raises: [].} =
  {.cast(gcsafe).}:
    try:
      self.resetDirty()
      debuggerChrome(nui, self, "debugger-variables", "Variables"):
        nui.node("debugger-var-body"):
          discard nui.fillX().fillY()
          var scopeCount = 0
          try:
            if debugger.currentScopes().getSome(scopes):
              scopeCount = scopes[].scopes.len
          except:
            discard
          if scopeCount == 0:
            debuggerEmpty(nui, "No variables")
          else:
            let cache = beginVarFrame(self, debugger)
            if cache == nil:
              debuggerEmpty(nui, "No variables")
            else:
              var options = defaultTreeTableOptions()
              options.columns = @[tableColumnProportional(1), tableColumnProportional(1), tableColumnProportional(1)]
              options.hideRoot = true
              options.showColumnLines = true
              options.showIndentationLines = true
              options.highlightHoveredRow = true
              options.expandCollapseButtons = false
              var root = DebuggerVariablesCursor(cache: cache)
              root.applyVarLocation(DebuggerVarLocation(
                key: DebuggerVarRootKey, scopeIdx: -1, index: 0, path: @[],
                name: "Variables",
                container: 0.VariablesReference))
              nui.treeTable(root, options, renderDebuggerVariablesRow)
    except:
      discard

proc createOutputUINui*(self: OutputView, nui: var UiBuilder,
    debugger: Debugger) {.gcsafe, raises: [].} =
  {.cast(gcsafe).}:
    try:
      self.resetDirty()
      debuggerChrome(nui, self, "debugger-output", "Output"):
        nui.node("debugger-output-body"):
          discard nui.fillX().fillY()
          try:
            if debugger.outputEditor != nil:
              debugger.outputEditor.active = self.active
              debugger.outputEditor.renderNui(nui)
            else:
              debuggerEmpty(nui, "No output")
          except:
            discard
    except:
      discard

# NUI-GAP vs the removed legacy renderer: breakpoint state shows as on/off
# text instead of ✅/❌ markers (see §25).
proc createToolbarUINui*(self: ToolbarView, nui: var UiBuilder,
    debugger: Debugger) {.gcsafe, raises: [].} =
  {.cast(gcsafe).}:
    try:
      self.resetDirty()
      var status = "Debugger"
      var description = ""
      try:
        case debugger.debuggerState
        of DebuggerState.None: status.add " - Not started"
        of DebuggerState.Starting: status.add " - Starting"
        of DebuggerState.Paused:
          status.add " - Paused"
          if debugger.currentStopData.reason != "":
            status.add " (" & debugger.currentStopData.reason & ")"
          if debugger.currentStopData.description.isSome:
            description = debugger.currentStopData.description.get("")
        of DebuggerState.Running: status.add " - Running"
        if debugger.lastConfiguration.getSome(config):
          status.add " - " & config
        if debugger.breakpointsEnabled:
          status.add " - Breakpoints: on"
        else:
          status.add " - Breakpoints: off"
      except:
        discard
      debuggerChrome(nui, self, "debugger-toolbar", "Debugger"):
        nui.node:
          discard nui.fillX().fitY().textStyleIndex(
            int(UiStyleIndexDefaultText)).wrapText().text(status)
        if description.len > 0:
          nui.node:
            discard nui.fillX().fitY().textStyleIndex(
              int(UiStyleIndexDefaultText)).wrapText().text(description)
    except:
      discard
