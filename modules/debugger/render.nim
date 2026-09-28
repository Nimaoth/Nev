import std/[strformat, options, tables, sets, strutils]
import misc/[util, custom_logger]
import platform
import view, document_editor, layout/layout, service
import types_impl, debugger, dap_client

from nuigi import UiBuilder, UiBackendType, UiStyleIndex, UiTextStyleIndex,
  UiNodeStorageData, text, textStyleIndex, fit, fitY, node, fillX, fillY,
  fillBackground, styleIndex, backgroundColor, accentVariation, themeStyle,
  padding, gap, layoutVertical, layoutHorizontal, currentNode, currentNodeIndex,
  nodeStorage, nodeStorageGet, nodeStorageParent, nodeStorageParents,
  nodeIdValue, wasClicked, wasHovered, wrapText
import nuigi/widgets/dynamic_virtuallist
import nuigi/widgets/tree_table
from nuigi/widgets import tableColumnProportional
import nuigi/debug/profiler
from std/unicode import runeLen, runeSubStr

# Mark this entire file as used, otherwise we get warnings when importing it but only calling a method
{.used.}

logCategory "widget_builder_debugger"

const debuggerMaxVarRows = 2000

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
    let baseBg = nui.themeStyle(UiStyleIndexPanel)[].fillColor
    let bgColor =
      if view.active: accentVariation(baseBg, 0.06'f32, 1.12'f32)
      else: baseBg
    let headerBase = nui.themeStyle(UiStyleIndexHeader)[].fillColor
    let headerColor =
      if view.active: accentVariation(headerBase, 0.04'f32, 1.10'f32)
      else: headerBase
    nui.layoutVertical(rootName):
      discard nui.fillX().fillY().fillBackground().styleIndex(
        UiStyleIndexPanel).backgroundColor(bgColor).padding(4).gap(4)
      try:
        if nui.wasClicked(includeChildren = true):
          getServiceChecked(LayoutService).tryActivateView(view)
      except:
        discard
      nui.layoutHorizontal(rootName & "-header"):
        discard nui.fillX().fitY().fillBackground().styleIndex(
          UiStyleIndexHeader).backgroundColor(headerColor).padding(4).gap(4)
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

# Variables tree table: DebuggerVariablesCursor (declared in types_impl)
# navigates scopes/variables live through the debugger tables (cf.
# file_explorer's VirtualFileSystemCursor), so visible rows resolve on demand
# and never need precalculating. Index-based paths/keys stay valid across DAP
# refetches that remap VariablesReferences (see updateVariables); expansion is
# owned by the tree widget, with collapsedVariables kept in sync for the legacy
# renderer and keyboard navigation.

type DebuggerVarDetail = tuple
  ok: bool
  name: string
  typ: string
  value: string
  childRef: VariablesReference
  cached: bool
  count: int

proc childCountAt(c: DebuggerVariablesCursor, path: seq[int]): int {.gcsafe, raises: [].} =
  ## Live child count for an index path: scopes at the root, cached variables
  ## below. Uncached containers report 0 until requestDebuggerChildren fetches
  ## them (file_explorer cache-miss pattern).
  prof("childCountAt")
  try:
    if c.debugger == nil:
      return 0
    let scopes = c.debugger.currentScopes().getOr:
      return 0
    let ids = c.debugger.currentVariablesContext().getOr:
      return 0
    if path.len == 0:
      return scopes[].scopes.len
    let scopeIdx = path[0]
    if scopeIdx < 0 or scopeIdx > scopes[].scopes.high:
      return 0
    var container = scopes[].scopes[scopeIdx].variablesReference
    for j in 1 ..< path.len:
      if container == 0.VariablesReference:
        return 0
      if not c.debugger.variables.contains(ids & container):
        return 0
      let vars = c.debugger.variables[ids & container]
      let idx = path[j]
      if idx < 0 or idx > vars.variables.high:
        return 0
      container = vars.variables[idx].variablesReference
    if container == 0.VariablesReference:
      return 0
    if not c.debugger.variables.contains(ids & container):
      return 0
    return c.debugger.variables[ids & container].variables.len
  except:
    return 0

proc resolveDebuggerVar(c: DebuggerVariablesCursor,
    path: seq[int]): DebuggerVarDetail {.gcsafe, raises: [].}

proc nameAt(c: DebuggerVariablesCursor, path: seq[int]): string {.gcsafe, raises: [].} =
  try:
    if c.debugger == nil:
      return ""
    if path.len == 0:
      return "Variables"
    let scopes = c.debugger.currentScopes().getOr:
      return ""
    if path[0] < 0 or path[0] > scopes[].scopes.high:
      return ""
    if path.len == 1:
      return scopes[].scopes[path[0]].name
    let d = c.resolveDebuggerVar(path)
    if d.ok:
      return d.name
    return ""
  except:
    return ""

proc resolveDebuggerVar(c: DebuggerVariablesCursor,
    path: seq[int]): DebuggerVarDetail {.gcsafe, raises: [].} =
  prof("resolveDebuggerVar")
  result = (false, "", "", "", 0.VariablesReference, false, 0)
  try:
    if c.debugger == nil or path.len == 0:
      return
    let scopes = c.debugger.currentScopes().getOr:
      return
    let ids = c.debugger.currentVariablesContext().getOr:
      return
    let scopeIdx = path[0]
    if scopeIdx < 0 or scopeIdx > scopes[].scopes.high:
      return
    if path.len == 1:
      let scope = scopes[].scopes[scopeIdx]
      let cached = c.debugger.variables.contains(ids & scope.variablesReference)
      let count =
        if cached: c.debugger.variables[ids & scope.variablesReference].variables.len
        else: 0
      return (true, scope.name, "", "", scope.variablesReference, cached, count)
    var container = scopes[].scopes[scopeIdx].variablesReference
    for j in 1 ..< path.high:
      if not c.debugger.variables.contains(ids & container):
        return
      let vars = c.debugger.variables[ids & container]
      let idx = path[j]
      if idx < 0 or idx > vars.variables.high:
        return
      container = vars.variables[idx].variablesReference
      if container == 0.VariablesReference:
        return
    if not c.debugger.variables.contains(ids & container):
      return
    let vars = c.debugger.variables[ids & container]
    let idx = path[^1]
    if idx < 0 or idx > vars.variables.high:
      return
    let va = vars.variables[idx]
    let cached = va.variablesReference != 0.VariablesReference and
      c.debugger.variables.contains(ids & va.variablesReference)
    let count =
      if cached: c.debugger.variables[ids & va.variablesReference].variables.len
      else: 0
    return (true, va.name, va.`type`.get(""), va.value, va.variablesReference,
      cached, count)
  except:
    result = (false, "", "", "", 0.VariablesReference, false, 0)

method clone*(c: DebuggerVariablesCursor): TreeCursor {.gcsafe, raises: [].} =
  try:
    prof("clone")
    result = DebuggerVariablesCursor(debugger: c.debugger, view: c.view)
    result.path = c.path
    result.index = c.index
    result.fieldName = c.fieldName
  except:
    result = nil

method cursorKey*(c: DebuggerVariablesCursor): string {.gcsafe, raises: [].} =
  try:
    prof("cursorKey")
    return debuggerVarCursorKey(c.path)
  except:
    return "dbgvar:root"

method childCount*(c: DebuggerVariablesCursor): int {.gcsafe, raises: [].} =
  try:
    prof("childCount")
    return c.childCountAt(c.path)
  except:
    return 0

method enterChild*(c: DebuggerVariablesCursor): bool {.gcsafe, raises: [].} =
  try:
    prof("enterChild")
    if c.childCount() <= 0:
      return false
    c.path.add(0)
    c.index = 0
    c.fieldName = c.nameAt(c.path)
    return true
  except:
    return false

method exitChild*(c: DebuggerVariablesCursor): bool {.gcsafe, raises: [].} =
  try:
    prof("exitChild")
    if c.path.len == 0:
      return false
    discard c.path.pop()
    c.index = if c.path.len > 0: c.path[^1] else: 0
    c.fieldName = c.nameAt(c.path)
    return true
  except:
    return false

proc siblingCountAt(c: DebuggerVariablesCursor, path: seq[int]): int {.gcsafe, raises: [].} =
  ## Children of the parent of `path` (i.e. siblings including self).
  try:
    if path.len == 0:
      return 0
    if path.len == 1:
      if c.debugger == nil:
        return 0
      let scopes = c.debugger.currentScopes().getOr:
        return 0
      return scopes[].scopes.len
    return c.childCountAt(path[0 ..< path.high])
  except:
    return 0

method moveNext*(c: DebuggerVariablesCursor, count: int = 1): bool {.gcsafe, raises: [].} =
  try:
    if c.path.len == 0:
      return false
    let n = c.siblingCountAt(c.path)
    let target = c.path[^1] + count
    if target < 0 or target >= n:
      return false
    c.path[^1] = target
    c.index = target
    c.fieldName = c.nameAt(c.path)
    return true
  except:
    return false

method movePrev*(c: DebuggerVariablesCursor, count: int = 1): bool {.gcsafe, raises: [].} =
  try:
    if c.path.len == 0:
      return false
    let n = c.siblingCountAt(c.path)
    let target = c.path[^1] - count
    if target < 0 or target >= n:
      return false
    c.path[^1] = target
    c.index = target
    c.fieldName = c.nameAt(c.path)
    return true
  except:
    return false

method updatePath*(c: DebuggerVariablesCursor, path: seq[int]) {.gcsafe, raises: [].} =
  try:
    c.path = path
    c.index = if path.len > 0: path[^1] else: 0
    c.fieldName = c.nameAt(path)
  except:
    discard

method replacePathPrefix*(c: DebuggerVariablesCursor, oldPrefixLen: int,
    newPrefix: seq[int]) {.gcsafe, raises: [].} =
  try:
    if oldPrefixLen == newPrefix.len:
      for i in 0 ..< newPrefix.len:
        if i < c.path.len:
          c.path[i] = newPrefix[i]
    else:
      let suffixLen = max(0, c.path.len - oldPrefixLen)
      var newPath = newSeq[int](newPrefix.len + suffixLen)
      for i in 0 ..< newPrefix.len:
        newPath[i] = newPrefix[i]
      for i in 0 ..< suffixLen:
        newPath[newPrefix.len + i] = c.path[oldPrefixLen + i]
      c.path = newPath
    c.index = if c.path.len > 0: c.path[^1] else: 0
    c.fieldName = c.nameAt(c.path)
  except:
    discard

method resolveChild*(c: DebuggerVariablesCursor,
    child: TreeCursor): TreeCursor {.gcsafe, raises: [].} =
  try:
    if child == nil or not (child of DebuggerVariablesCursor):
      return nil
    let e = DebuggerVariablesCursor(child)
    if e.path.len != c.path.len + 1:
      return nil
    for i in 0 ..< c.path.len:
      if e.path[i] != c.path[i]:
        return nil
    if e.path[^1] < 0 or e.path[^1] >= c.childCount():
      return nil
    result = DebuggerVariablesCursor(debugger: c.debugger, view: c.view)
    result.path = e.path
    result.index = e.path[^1]
    result.fieldName = c.nameAt(e.path)
  except:
    result = nil

proc toVariableCursor(c: DebuggerVariablesCursor): Option[VariableCursor] {.gcsafe, raises: [].} =
  ## Best-effort mapping back to the selection model, resolving live varRefs.
  try:
    if c.debugger == nil or c.path.len == 0 or c.path[0] < 0:
      return VariableCursor.none
    let scopes = c.debugger.currentScopes().getOr:
      return VariableCursor.none
    let ids = c.debugger.currentVariablesContext().getOr:
      return VariableCursor.none
    if c.path[0] > scopes[].scopes.high:
      return VariableCursor.none
    if c.path.len == 1:
      return VariableCursor(scope: c.path[0]).some
    var pairs = newSeq[tuple[index: int, varRef: VariablesReference]]()
    var container = scopes[].scopes[c.path[0]].variablesReference
    for j in 1 ..< c.path.len:
      if not c.debugger.variables.contains(ids & container):
        return VariableCursor.none
      let vars = c.debugger.variables[ids & container]
      if c.path[j] < 0 or c.path[j] > vars.variables.high:
        return VariableCursor.none
      pairs.add((c.path[j], container))
      container = vars.variables[c.path[j]].variablesReference
    return VariableCursor(scope: c.path[0], path: pairs).some
  except:
    return VariableCursor.none

proc renderDebuggerVariablesRow(b: var UiBuilder, cursor: TreeCursor,
    index: int) {.nimcall, gcsafe, raises: [].} =
  discard index
  try:
    if cursor == nil or not (cursor of DebuggerVariablesCursor):
      return
    let c = DebuggerVariablesCursor(cursor)
    if c.debugger == nil or c.view == nil or c.path.len == 0:
      return
    let view = c.view
    let debugger = c.debugger
    let ids = debugger.currentVariablesContext().getOr:
      return
    let d = c.resolveDebuggerVar(c.path)
    if not d.ok:
      return
    if d.childRef != 0.VariablesReference and not d.cached:
      view.requestVariableChildren(debugger, ids, d.childRef)
    var selected = false
    try:
      if view.variablesCursor.scope == c.path[0]:
        selected = view.variablesCursor.variableCursorIndexPath() == c.path
    except:
      discard
    # Background only for the selected row; the tree widget itself owns hover
    # and indentation guides (no custom +/- markers: the chevron shows state).
    if selected:
      discard b.fillBackground().styleIndex(UiStyleIndexMenuItemHover)
    else:
      discard b.styleIndex(UiStyleIndexMenuItem)
    let rowTextStyle = int(if selected:
      UiStyleIndexMenuItemHoverText
    else:
      UiStyleIndexMenuItemText)
    b.node:
      discard b.fit().textStyleIndex(rowTextStyle).text(d.name)
    if b.wasClicked(includeChildren = true):
      let sel = c.toVariableCursor()
      if sel.isSome:
        view.variablesCursor = sel.get()
        view.markDirty()
    b.node:
      discard b.fit().textStyleIndex(rowTextStyle).text(d.typ)
    b.node:
      let firstLine =
        try: d.value.splitLines()[0]
        except: d.value
      discard b.fit().textStyleIndex(rowTextStyle).text(truncDebuggerText(firstLine, 160))
    # Chevron clicks toggle tree state only; mirror into collapsedVariables so
    # keyboard navigation (which reads it) stays coherent.
    for storage in b.nodeStorageParents():
      if storage of TreeTable:
        let tree = TreeTable(storage)
        if d.childRef != 0.VariablesReference:
          let ck = ids & d.childRef
          if isVarTreeExpanded(tree, c.cursorKey()) and view.isCollapsed(ck):
            view.collapsedVariables.excl(ck)
          elif not isVarTreeExpanded(tree, c.cursorKey()) and
              not view.isCollapsed(ck):
            view.collapsedVariables.incl(ck)
        break
  except:
    discard

proc expandVarSubtree(self: VariablesView, debugger: Debugger,
    ids: (ThreadId, FrameId), tree: TreeTable, parentPath: seq[int],
    depth: int, budget: var int) {.gcsafe, raises: [].} =
  try:
    if depth > 24 or budget <= 0 or tree == nil:
      return
    let probe = DebuggerVariablesCursor(debugger: debugger, view: self)
    probe.path = parentPath
    let n = probe.childCount()
    for i in 0 ..< n:
      if budget <= 0:
        break
      var childPath = newSeq[int](parentPath.len + 1)
      for j in 0 ..< parentPath.len:
        childPath[j] = parentPath[j]
      childPath[^1] = i
      let d = probe.resolveDebuggerVar(childPath)
      if not d.ok or d.childRef == 0.VariablesReference or not d.cached:
        continue
      if self.isCollapsed(ids & d.childRef):
        continue
      var cur = DebuggerVariablesCursor(debugger: debugger, view: self)
      cur.path = childPath
      cur.index = i
      cur.fieldName = d.name
      tree.expandNode(cur)
      dec budget
      self.expandVarSubtree(debugger, ids, tree, childPath, depth + 1, budget)
  except:
    discard

proc bulkSyncVarTree(self: VariablesView, debugger: Debugger,
    ids: (ThreadId, FrameId)) {.gcsafe, raises: [].} =
  ## Rebuilds tree expansion from collapsedVariables after context changes or
  ## first render (the tree starts fully collapsed; the legacy view starts
  ## expanded). Capped like the old row precalculation was.
  try:
    var tree = self.varTree
    if tree == nil:
      return
    let scopes = debugger.currentScopes().getOr:
      return
    tree.collapseAll()
    var budget = debuggerMaxVarRows
    for scopeIdx in 0 .. scopes[].scopes.high:
      if budget <= 0:
        break
      let scope = scopes[].scopes[scopeIdx]
      if self.isCollapsed(ids & scope.variablesReference):
        continue
      var cur = DebuggerVariablesCursor(debugger: debugger, view: self)
      cur.path = @[scopeIdx]
      cur.index = scopeIdx
      cur.fieldName = scope.name
      tree.expandNode(cur)
      dec budget
      self.expandVarSubtree(debugger, ids, tree, cur.path, 0, budget)
    self.markDirty()
  except:
    discard

# NUI-GAP vs the removed legacy renderer (custom render-command tree): no
# multiline values, no valueChanged background, no filter match highlight, no
# evaluation row, no drag-resize/detach, no SizeToContent modes; rows show
# truncated single-line values with click to select and chevron
# expand/collapse, and the selected row is not keyboard-followed (see §25).
proc createVariablesUINui*(self: VariablesView, nui: var UiBuilder,
    debugger: Debugger) {.gcsafe, raises: [].} =
  {.cast(gcsafe).}:
    try:
      self.resetDirty()
      var title = "Variables"
      try:
        if self.variablesFilter.len > 0:
          title.add &" - Filter: {self.variablesFilter}"
      except:
        discard
      debuggerChrome(nui, self, "debugger-variables", title):
        nui.node("debugger-var-body"):
          discard nui.fillX().fillY()
          var scopeCount = 0
          try:
            if debugger.currentScopes().getSome(scopes):
              scopeCount = scopes[].scopes.len
          except:
            discard
          let idsOpt =
            try: debugger.currentVariablesContext()
            except: none[(ThreadId, FrameId)]()
          if scopeCount == 0 or idsOpt.isNone:
            debuggerEmpty(nui, "No variables")
          else:
            var options = defaultTreeTableOptions()
            options.columns = @[tableColumnProportional(1), tableColumnProportional(1), tableColumnProportional(1)]
            options.hideRoot = true
            options.showColumnLines = true
            options.showIndentationLines = true
            options.highlightHoveredRow = true
            options.expandCollapseButtons = false
            # Ensure the container holds a TreeTable (a stale wrong-typed
            # storage from a previous renderer generation is replaced).
            let existingStorage = nui.nodeStorageGet(nui.currentNode)
            var tree: TreeTable = nil
            if existingStorage != nil and existingStorage of TreeTable:
              tree = cast[TreeTable](existingStorage)
            else:
              tree = TreeTable()
              nui.nodeStorage(nui.currentNode, tree)
            var root = DebuggerVariablesCursor(debugger: debugger, view: self)
            root.path = @[]
            root.index = 0
            root.fieldName = "Variables"
            let bodyId = nui.currentNode.id
            nui.treeTable(root, options, renderDebuggerVariablesRow)
            # Adopt the live storage and rebuild expansion when the context is
            # new (first render, storage replacement, thread/frame switch).
            # The id check guards against widget internals leaving a different
            # node current; a miss simply retries next frame (valid stays false).
            try:
              if nui.currentNode.id.nodeIdValue() == bodyId.nodeIdValue():
                let live = cast[TreeTable](nui.nodeStorageGet(nui.currentNode))
                if live != nil:
                  let ids = idsOpt.get()
                  if not self.varTreeValid or self.varTree != live or
                      self.varTreeIds != ids:
                    self.varTree = live
                    self.varTreeIds = ids
                    self.varTreeValid = true
                    self.bulkSyncVarTree(debugger, ids)
                  else:
                    self.varTree = live
            except:
              discard
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
