#use layout command_service workspace vfs_service
import std/[algorithm, json, os, sets, tables]
import service, view
import component
import nuigi/debug/profiler

export component

const currentSourcePath2 = currentSourcePath()
include module_base

when implModule:
  import misc/[custom_async, custom_logger, id, myjsonutils]
  import layout/layout, command_service, workspace, vfs, vfs_service
  from nuigi import UiBuilder, UiStyleIndex, UiTextStyleIndex,
    fillX, fillY, fit, fitY, fillBackground, styleIndex, textStyleIndex,
    text, padding, gap, layoutVertical, layoutHorizontal,
    layoutHorizontalReverse, node, wasClicked, size, alignCenter,
    UiBackendType, absoluteNodePosPrev, previousNodeIndex
  from nuigi/widgets import button, menu, menuItem, tableColumnFill,
    tableColumnFit
  import nuigi/widgets/tree_table

  logCategory "file-explorer"

  type
    FileExplorerRoot = enum
      VirtualFileSystemRoot
      WorkspaceRoot

    VirtualFileSystemEntry = object
      name: string
      kind: FileKind

    VirtualFileSystemCursorCache = ref object
      vfs: VFS
      listings: Table[string, seq[VirtualFileSystemEntry]]
      loading: HashSet[string]
      onChanged: proc() {.gcsafe, raises: [].}

    VirtualFileSystemCursorLocation = ref object
      parent: VirtualFileSystemCursorLocation
      fullPath: string
      parentPath: string
      fieldName: string
      path: seq[int]
      index: int
      kind: FileKind

    VirtualFileSystemCursor = ref object of TreeCursor
      cache: VirtualFileSystemCursorCache
      location: VirtualFileSystemCursorLocation

    FileExplorerView* = ref object of View
      workspace: Workspace
      vfs: VFS
      cursor: VirtualFileSystemCursor
      rootPath: string
      root: FileExplorerRoot = WorkspaceRoot
      rootMenuOpen: bool

  var gFileExplorerView: FileExplorerView

  func fullPath(cursor: VirtualFileSystemCursor): string {.inline.} =
    cursor.location.fullPath

  func kind(cursor: VirtualFileSystemCursor): FileKind {.inline.} =
    cursor.location.kind

  proc pathWithIndex(path: seq[int], index: int): seq[int] =
    result = newSeqOfCap[int](path.len + 1)
    result.add(path)
    result.add(index)

  proc applyLocation(
      cursor: VirtualFileSystemCursor,
      location: VirtualFileSystemCursorLocation) =
    cursor.location = location
    cursor.fieldName = location.fieldName
    cursor.path = location.path
    cursor.index = location.index

  proc cursorAt(
      cursor: VirtualFileSystemCursor,
      location: VirtualFileSystemCursorLocation): VirtualFileSystemCursor =
    result = VirtualFileSystemCursor(cache: cursor.cache)
    result.applyLocation(location)

  proc copyPathPrefix(path: seq[int], count: int): seq[int] =
    result = newSeqOfCap[int](count)
    for index in 0 ..< count:
      result.add(path[index])

  proc rebaseLocation(
      location: VirtualFileSystemCursorLocation,
      path: seq[int],
      depth: int): VirtualFileSystemCursorLocation =
    var parent: VirtualFileSystemCursorLocation = nil
    if location.parent != nil:
      parent = location.parent.rebaseLocation(path, depth - 1)
    result = VirtualFileSystemCursorLocation(
      parent: parent,
      fullPath: location.fullPath,
      parentPath: location.parentPath,
      fieldName: location.fieldName,
      path: copyPathPrefix(path, depth),
      index: if depth > 0: path[depth - 1] else: 0,
      kind: location.kind)

  proc requestListing(
      cache: VirtualFileSystemCursorCache,
      directoryPath: string): ptr seq[VirtualFileSystemEntry] =
    prof("requestListing")
    if directoryPath notin cache.listings:
      prof("list")
      cache.listings[directoryPath] = @[]
      if directoryPath notin cache.loading:
        prof("load")
        cache.loading.incl(directoryPath)
        proc loadListing() {.async: (raises: []).} =
          let listing = await cache.vfs.getDirectoryListing(directoryPath)
          var folders = listing.folders
          var files = listing.files
          folders.sort(system.cmp[string])
          files.sort(system.cmp[string])
          var entries = newSeqOfCap[VirtualFileSystemEntry](
            folders.len + files.len)
          for name in folders:
            entries.add VirtualFileSystemEntry(
              name: name,
              kind: FileKind.Directory)
          for name in files:
            entries.add VirtualFileSystemEntry(
              name: name,
              kind: FileKind.File)
          cache.listings[directoryPath] = entries
          cache.loading.excl(directoryPath)
          if cache.onChanged != nil:
            cache.onChanged()
        asyncSpawn loadListing()
    return cache.listings.mgetOrPut(directoryPath, @[]).addr

  proc listedChild(
      cursor: VirtualFileSystemCursor,
      parent: VirtualFileSystemCursorLocation,
      entry: VirtualFileSystemEntry,
      index: int): VirtualFileSystemCursorLocation =
    VirtualFileSystemCursorLocation(
      parent: parent,
      fullPath: parent.fullPath // entry.name,
      parentPath: parent.fullPath,
      fieldName: entry.name,
      path: pathWithIndex(parent.path, index),
      index: index,
      kind: entry.kind)

  method clone(cursor: VirtualFileSystemCursor): TreeCursor =
    cursor.cursorAt(cursor.location)

  method updatePath(cursor: VirtualFileSystemCursor, path: seq[int]) =
    cursor.applyLocation(cursor.location.rebaseLocation(path, path.len))

  method replacePathPrefix(
      cursor: VirtualFileSystemCursor,
      oldPrefixLen: int,
      newPrefix: seq[int]) =
    prof("replacePathPrefix")
    if oldPrefixLen != newPrefix.len:
      let suffixLen = max(0, cursor.path.len - oldPrefixLen)
      var replacedPath = newSeq[int](newPrefix.len + suffixLen)
      for index in 0 ..< newPrefix.len:
        replacedPath[index] = newPrefix[index]
      for index in 0 ..< suffixLen:
        replacedPath[newPrefix.len + index] = cursor.path[oldPrefixLen + index]
      cursor.applyLocation(cursor.location.rebaseLocation(
        replacedPath, replacedPath.len))
      return

    var sharedDepth = 0
    while sharedDepth < newPrefix.len and
        cursor.path[sharedDepth] == newPrefix[sharedDepth]:
      inc sharedDepth
    if sharedDepth == newPrefix.len:
      return

    var oldLocations: seq[VirtualFileSystemCursorLocation] = @[]
    var sharedLocation = cursor.location
    while sharedLocation.path.len > sharedDepth:
      oldLocations.add(sharedLocation)
      if sharedLocation.parent == nil:
        break
      sharedLocation = sharedLocation.parent

    var parentLocation = sharedLocation
    for locationIndex in countdown(oldLocations.high, 0):
      let oldLocation = oldLocations[locationIndex]
      var path = newSeq[int](oldLocation.path.len)
      for pathIndex in 0 ..< path.len:
        path[pathIndex] = if pathIndex < newPrefix.len:
          newPrefix[pathIndex]
        else:
          oldLocation.path[pathIndex]
      parentLocation = VirtualFileSystemCursorLocation(
        parent: parentLocation,
        fullPath: oldLocation.fullPath,
        parentPath: oldLocation.parentPath,
        fieldName: oldLocation.fieldName,
        path: path,
        index: path[^1],
        kind: oldLocation.kind)
    cursor.applyLocation(parentLocation)

  method cursorKey(cursor: VirtualFileSystemCursor): string =
    cursor.fullPath

  method childCount(cursor: VirtualFileSystemCursor): int =
    if cursor.kind != FileKind.Directory:
      return 0
    cursor.cache.requestListing(cursor.fullPath)[].len

  method resolveChild(
      cursor: VirtualFileSystemCursor,
      child: TreeCursor): TreeCursor =
    prof("resolveChild")
    let expected = VirtualFileSystemCursor(child)
    if expected.location.parentPath != cursor.fullPath:
      return nil
    let entries = cursor.cache.requestListing(cursor.fullPath)
    var foundIndex = -1
    if expected.index >= 0 and expected.index < entries[].len and
        entries[][expected.index].name == expected.fieldName:
      foundIndex = expected.index
    else:
      for index, entry in entries[]:
        if entry.name == expected.fieldName and entry.kind == expected.kind:
          foundIndex = index
          break
    if foundIndex < 0:
      return nil
    cursor.cursorAt(cursor.listedChild(
      cursor.location, entries[][foundIndex], foundIndex))

  method enterChild(cursor: VirtualFileSystemCursor): bool =
    prof("enterChild")
    if cursor.kind != FileKind.Directory:
      return false
    let entries = cursor.cache.requestListing(cursor.fullPath)
    if entries[].len == 0:
      return false
    cursor.applyLocation(cursor.listedChild(
      cursor.location, entries[][0], 0))
    true

  proc moveBy(cursor: VirtualFileSystemCursor, count: int): bool =
    prof("moveBy")
    if cursor.location.parent == nil:
      return false
    let entries = cursor.cache.requestListing(cursor.location.parentPath)
    let targetIndex = cursor.index + count
    if targetIndex < 0 or targetIndex >= entries[].len:
      return false
    cursor.applyLocation(cursor.listedChild(
      cursor.location.parent, entries[][targetIndex], targetIndex))
    true

  method moveNext(
      cursor: VirtualFileSystemCursor, count: int = 1): bool =
    cursor.moveBy(count)

  method movePrev(
      cursor: VirtualFileSystemCursor, count: int = 1): bool =
    cursor.moveBy(-count)

  method exitChild(cursor: VirtualFileSystemCursor): bool =
    if cursor.location.parent == nil:
      return false
    cursor.applyLocation(cursor.location.parent)
    true

  proc virtualFileSystemCursor(
      vfs: VFS,
      root: string,
      displayName: string,
      onChanged: proc() {.gcsafe, raises: [].}): VirtualFileSystemCursor =
    let cache = VirtualFileSystemCursorCache(
      vfs: vfs,
      listings: initTable[string, seq[VirtualFileSystemEntry]](),
      loading: initHashSet[string](),
      onChanged: onChanged)
    result = VirtualFileSystemCursor(cache: cache)
    result.applyLocation(VirtualFileSystemCursorLocation(
      fullPath: root,
      parentPath: parentDirectory(root),
      fieldName: displayName,
      path: @[],
      index: 0,
      kind: FileKind.Directory))

  proc selectedRootPath(view: FileExplorerView): string =
    case view.root
    of VirtualFileSystemRoot:
      result = ""
    of WorkspaceRoot:
      if view.workspace != nil and view.workspace.getWorkspacePath().len > 0:
        return "ws0://"
      try:
        result = getCurrentDir()
      except OSError:
        result = "."

  proc workspaceDisplayName(view: FileExplorerView): string =
    if view.workspace != nil:
      let workspacePath = view.workspace.getWorkspacePath()
      if workspacePath.len > 0:
        let name = workspacePath.splitPath.tail
        if name.len > 0:
          return name
    result = "Workspace"

  proc selectedRootDisplayName(view: FileExplorerView): string =
    case view.root
    of VirtualFileSystemRoot:
      result = "Virtual File System"
    of WorkspaceRoot:
      result = view.workspaceDisplayName()

  proc resetCursor(view: FileExplorerView) =
    let root = view.selectedRootPath()
    view.rootPath = root
    view.cursor = virtualFileSystemCursor(
      view.vfs,
      root,
      view.selectedRootDisplayName(),
      proc() {.gcsafe, raises: [].} = view.markDirty())

  proc selectRoot(view: FileExplorerView, root: FileExplorerRoot) =
    view.rootMenuOpen = false
    if view.root == root:
      return
    view.root = root
    view.resetCursor()
    view.markDirty()

  proc fileExplorerRefresh(view: FileExplorerView) {.gcsafe, raises: [].} =
    try:
      view.resetCursor()
      view.markDirty()
    except:
      log lvlError, "Failed to refresh file explorer"

  proc getFileExplorerView(): FileExplorerView =
    {.gcsafe.}:
      if gFileExplorerView.isNil:
        raise newException(ValueError, "File explorer view not initialized")
      gFileExplorerView

  proc renderFileExplorerRow(
      b: var UiBuilder, cursor: TreeCursor, index: int) {.nimcall, gcsafe, raises: [].} =
    try:
      let fileCursor = VirtualFileSystemCursor(cursor)
      let clicked = b.wasClicked(includeChildren = true)

      b.layoutHorizontal:
        discard b.fillX().fitY().gap(4)
        b.node:
          if b.backendType == UiBackendType.Terminal:
            discard b.size(1, 1).alignCenter()
          else:
            discard b.size(14, 14).alignCenter()
          discard b.textStyleIndex(int(UiStyleIndexMutedText))
            .text(if fileCursor.kind == FileKind.Directory: "📁" else: "📄")
        b.node:
          discard b.fillX().fitY()
            .textStyleIndex(int(UiStyleIndexDefaultText))
            .text(cursor.fieldName)
      b.node:
        prof("rrrrrrrrrrr")
        let childCount = if fileCursor.kind == FileKind.Directory:
          cursor.childCount()
        else:
          0
        discard b.fit().textStyleIndex(int(UiStyleIndexSmallText))
          .text(if fileCursor.kind == FileKind.Directory: $childCount else: "")

      if clicked and fileCursor.kind == FileKind.File:
        discard getServiceChecked(LayoutService).openFile(fileCursor.fullPath)
    except:
      discard

  proc renderFileExplorerNui(
      self: FileExplorerView, nui: var UiBuilder) {.gcsafe, raises: [].} =
    {.cast(gcsafe).}:
      self.resetDirty()
      let root = self.selectedRootPath()
      if self.cursor == nil or self.rootPath != root:
        self.resetCursor()

      template rootMenuItem(label: string, root: FileExplorerRoot) =
        nui.menuItem:
          nui.node:
            discard nui.fillX().fitY().padding(1)
              .textStyleIndex(int(UiStyleIndexMenuItemText)).text(label)
        do:
          discard
        do:
          self.selectRoot(root)

      nui.layoutVertical("file-explorer"):
        discard nui.fillX().fillY().styleIndex(UiStyleIndexPanel)
          .fillBackground().padding(4).gap(4)
        if nui.wasClicked(includeChildren = true):
          getServiceChecked(LayoutService).tryActivateView(self)

        nui.layoutHorizontal("file-explorer-header"):
          discard nui.fillX().fitY().styleIndex(UiStyleIndexHeader)
            .fillBackground().padding(4).gap(4)
          nui.node:
            discard nui.fit().textStyleIndex(int(UiStyleIndexHeaderText))
              .text("File Explorer")
          nui.layoutHorizontalReverse:
            discard nui.fillX().fitY().gap(4)
            if nui.button("Refresh"):
              self.fileExplorerRefresh()
            let rootMenuButtonIndex = nui.frame.nodes.len
            if nui.button("…"):
              self.rootMenuOpen = not self.rootMenuOpen
            let rootMenuButtonNode = nui.frame.nodes[rootMenuButtonIndex]
            let rootMenuPosition = nui.absoluteNodePosPrev(
              rootMenuButtonNode.id, rootMenuButtonIndex)
            nui.menu(self.rootMenuOpen,
                rootMenuPosition.x,
                rootMenuPosition.y + rootMenuButtonNode.size.y):
              rootMenuItem("Virtual File System", VirtualFileSystemRoot)
              rootMenuItem("Workspace", WorkspaceRoot)

        nui.layoutVertical("file-explorer-tree"):
          discard nui.fillX().fillY()
          if self.cursor != nil:
            var options = defaultTreeTableOptions()
            options.columns = @[
              tableColumnFill(),
              tableColumnFit(),
            ]
            options.hideRoot = false
            options.showIndentationLines = true
            options.highlightHoveredRow = true
            options.expandCollapseButtons = false
            nui.treeTable(self.cursor, options, renderFileExplorerRow)
          else:
            nui.node:
              discard nui.fit().textStyleIndex(int(UiStyleIndexMutedText))
                .text("No workspace")

  proc kind(self: FileExplorerView): string = "file-explorer"
  proc desc(self: FileExplorerView): string = "File Explorer"
  proc display(self: FileExplorerView): string = "File Explorer"
  proc copy(self: FileExplorerView): View = self

  proc saveLayout(self: FileExplorerView, discardedViews: HashSet[Id]): JsonNode =
    result = newJObject()
    result["kind"] = "file-explorer".toJson

  proc saveState(self: FileExplorerView): JsonNode =
    result = newJObject()
    result["kind"] = "file-explorer".toJson

  proc newFileExplorerView(workspace: Workspace, vfs: VFS): FileExplorerView =
    result = FileExplorerView(workspace: workspace, vfs: vfs)
    result.renderNuiImpl = proc(
        view: View, nui: var UiBuilder) {.gcsafe, raises: [].} =
      renderFileExplorerNui(view.FileExplorerView, nui)
    result.kindImpl = proc(self: View): string = kind(self.FileExplorerView)
    result.descImpl = proc(self: View): string = desc(self.FileExplorerView)
    result.displayImpl = proc(self: View): string = display(self.FileExplorerView)
    result.copyImpl = proc(self: View): View = copy(self.FileExplorerView)
    result.saveLayoutImpl = proc(
        self: View, discardedViews: HashSet[Id]): JsonNode =
      saveLayout(self.FileExplorerView, discardedViews)
    result.saveStateImpl = proc(self: View): JsonNode =
      saveState(self.FileExplorerView)
    result.fileExplorerRefresh()

  proc fileExplorerToggle(view: FileExplorerView) {.gcsafe, raises: [].} =
    let layout = getServiceChecked(LayoutService)
    if layout.isViewVisible(view):
      layout.closeView(view, keepHidden = false, restoreHidden = false)
    else:
      view.fileExplorerRefresh()
      layout.addView(view, slot = "#small-left", focus = true)

  include generated/file_explorer_commands

  proc init_module_file_explorer*() {.cdecl, exportc, dynlib.} =
    let services = getServices()
    if services == nil:
      log lvlWarn, "Failed to initialize file explorer: no services found"
      return

    gFileExplorerView = newFileExplorerView(
      services.getServiceChecked(Workspace),
      services.getServiceChecked(VFSService).vfs)
    let view = gFileExplorerView
    let layout = services.getServiceChecked(LayoutService)

    layout.addViewFactory "file-explorer", proc(config: JsonNode): View {.raises: [].} =
      return view

    registerCommands(services.getServiceChecked(CommandService))