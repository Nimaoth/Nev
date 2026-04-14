import std/[options]
import misc/[delayed_task, id, myjsonutils, jsonex]
import nimsumtree/[rope]
import component, config_provider

export component

const currentSourcePath2 = currentSourcePath()
include module_base

declareSettings ContextLineSettings, "context-lines":
  declare enabled, bool, true
  declare style, string, "breadcrumb"
  declare separator, string, "»"
  declare show, RegexSetting, """(definition\.(.*))"""
  declare showConditionals, bool, true
  declare showClasses, bool, true
  declare showFunctions, bool, true
  declare showModules, bool, true

type
  ContextLineEntry* = object
    line*: int
    name*: string
    kindName*: string
    nameRange*: Range[Point]
    kindRange*: Range[Point]
    lineRange*: Range[Point]

  ContextLineComponent* = ref object of Component
    settings*: ContextLineSettings
    contextLines*: seq[ContextLineEntry]
    updateTask: DelayedTask
    parsedHandle: Id
    selectionChangedHandle: Id
    documentChangedHandle: Id
    currentCursor: Point

{.push gcsafe, raises: [].}

{.push rtl.}
proc getContextLineComponent*(self: ComponentOwner): Option[ContextLineComponent]
proc newContextLineComponent*(settings: ContextLineSettings): ContextLineComponent
proc contextlineComponentGetContextLines(self: ContextLineComponent): seq[ContextLineEntry]
{.pop.}

proc getContextLines*(self: ContextLineComponent): seq[ContextLineEntry] = contextlineComponentGetContextLines(self)

when implModule:
  import std/[tables, algorithm]
  import misc/[custom_logger, custom_async, util, arena, array_view, event, regex, timer]
  import nimsumtree/[sumtree]
  import document, document_editor, text_component, treesitter_component, text_editor_component
  import text/[custom_treesitter, syntax_map, treesitter_type_conv, treesitter_types]

  logCategory "contextline-component"

  let ContextLineComponentId = componentGenerateTypeId()

  proc getContextLineComponent*(self: ComponentOwner): Option[ContextLineComponent] =
    return self.getComponent(ContextLineComponentId).mapIt(it.ContextLineComponent)

  proc extractNameFromNode*(self: ContextLineComponent, node: TSNode, text: TextComponent): (Option[string], Range[Point]) =
    var nameNode = node.childByFieldName("name")
    if not nameNode.isNull:
      let range = nameNode.getRange.toRange
      return (some(text.content(range)), range)

    for i in 0..<node.namedChildCount:
      let child = node.namedChild(i)
      let childType = child.nodeType
      if childType in ["identifier", "type_identifier", "property_identifier"]:
        let range = child.getRange.toRange
        return (some(text.content(range)), range)

    return (string.none, Range[Point].default)

  proc getKindNameFromCapture*(captureKind: string): string =
    let idx = captureKind.find('.')
    if idx != -1:
      return captureKind[(idx + 1)..^1]
    return captureKind

  proc getKindName*(self: ContextLineComponent, nodeType: string): string =
    const kindNames = {
      "class_declaration": "class",
      "class": "class",
      "struct_declaration": "struct",
      "struct": "struct",
      "proc_declaration": "proc",
      "func_declaration": "func",
      "function_declaration": "function",
      "method_declaration": "method",
      "template_declaration": "template",
      "macro_declaration": "macro",
      "if_statement": "if",
      "elif_statement": "elif",
      "else_statement": "else",
      "for_statement": "for",
      "while_statement": "while",
      "case_statement": "case",
      "block_statement": "block",
      "module_clause": "module",
      "import_statement": "import",
    }.toTable()

    return kindNames.getOrDefault(nodeType, nodeType)

  proc shouldShowKindName*(self: ContextLineComponent, kindName: string): bool =
    case kindName
    of "class", "struct", "implementation":
      self.settings.showClasses.get()
    of "proc", "func", "function", "template", "macro", "iterator", "method":
      self.settings.showFunctions.get()
    of "module", "import":
      self.settings.showModules.get()
    of "if", "elif", "else", "for", "while", "case", "block", "try", "except", "switch":
      self.settings.showConditionals.get()
    else:
      false

  proc getNameAndKindFromNodeType*(self: ContextLineComponent, node: TSNode, text: TextComponent): (string, Option[string], Range[Point]) =
    let kindName = self.getKindName(node.nodeType)
    if not self.shouldShowKindName(kindName):
      return ("", string.none, Range[Point].default)

    let (name, nameRange) = self.extractNameFromNode(node, text)
    return (kindName, name, nameRange)

  proc contextlineComponentGetContextLines(self: ContextLineComponent): seq[ContextLineEntry] =
    return self.contextLines

  proc updateContextLines(self: ContextLineComponent, cursor: Point): Future[seq[ContextLineEntry]] {.async.} =
    let editor = self.owner.DocumentEditor
    let document = editor.currentDocument
    if document.isNil:
      return @[]

    let text = document.getTextComponent().getOr:
      return @[]
    let treesitter = document.getTreesitterComponent().getOr:
      return @[]
    if treesitter.tsLanguage.isNil:
      return @[]

    let byteOffset = text.content.toOffset(cursor)

    let syntaxMap = treesitter.syntaxMap.snapshot
    if syntaxMap.layerIndex.isNil:
      return @[]

    let layers = syntaxMap.layersOverlapping(byteOffset...byteOffset)

    var entries: seq[ContextLineEntry]

    let r = re(self.settings.show.getRegex())

    for i in countdown(layers.high, 0):
      let layerIndex = layers[i]
      let layer {.cursor.} = syntaxMap.layers[layerIndex]
      let tree = layer.tree
      var node = tree.root.descendantForRange((cursor...cursor).tsRange)

      while node != tree.root:
        let nodeRange = node.getRange
        let firstLineRange = TSRange(
          first: nodeRange.first,
          last: TSPoint(row: nodeRange.first.row, column: syntaxMap.rope.lineLen(nodeRange.first.row))
        )

        var name: Option[string]
        var kindName: string
        var nameRange: Range[Point]
        var kindRange: Range[Point]

        var matchesNode = false
        let tagsQuery = await treesitter.query("tags", language = layer.language)

        if tagsQuery.isSome:
          var arena = initArena()
          for match in tagsQuery.get.matches(node, firstLineRange, arena):
            var matchedName: string
            var matchedKind: string
            var matchedNameRange: Range[Point]
            var matchedKindRange: Range[Point]

            for capture in match.captures:
              let captureName = $capture.name
              let capRange = capture.node.getRange.toRange
              if captureName == "name":
                matchedName = text.content(capRange)
                matchedNameRange = capRange
              elif captureName.contains("."):
                matchedKind = captureName
                matchedKindRange = capRange
              if capture.node == node:
                matchesNode = true

            if matchedKind.len > 0:
              name = if matchedName.len > 0: some(matchedName) else: string.none
              kindName = if matchedKind.len > 0: matchedKind else: node.nodeType
              nameRange = matchedNameRange
              kindRange = matchedKindRange
              break

        elif kindName.len == 0:
          let (fallbackKind, fallbackName, fallbackNameRange) = self.getNameAndKindFromNodeType(node, text)
          matchesNode = true
          if fallbackKind.len > 0:
            kindName = fallbackKind
            name = fallbackName
            nameRange = fallbackNameRange
            kindRange = node.getRange.toRange

        if kindName.len > 0 and kindName.match(r) and matchesNode:
          let entry = ContextLineEntry(
            line: nodeRange.first.row.int,
            name: name.get(""),
            kindName: kindName,
            nameRange: nameRange,
            kindRange: kindRange,
            lineRange: firstLineRange.toRange,
          )
          entries.add entry

        node = node.parent

    entries.sort proc(a, b: ContextLineEntry): int = cmp(a.lineRange.a, b.lineRange.a)
    return entries

  proc scheduleUpdate(self: ContextLineComponent) =
    if self.updateTask.isNotNil:
      self.updateTask.schedule()

  proc handleDocumentChanged(self: ContextLineComponent, old: Document, new: Document) =
    if old.isNotNil:
      if self.parsedHandle != idNone() and old.getTreesitterComponent().getSome(treesitter):
        treesitter.syntaxMap.onParsed.unsubscribe(self.parsedHandle)
        self.parsedHandle = idNone()
      if self.selectionChangedHandle != idNone() and old.getTextEditorComponent().getSome(edit):
        edit.onSelectionsChanged2.unsubscribe(self.selectionChangedHandle)
        self.selectionChangedHandle = idNone()

    if new.isNil:
      self.contextLines.setLen(0)
      return

    let treesitter = new.getTreesitterComponent().getOr: return

    self.parsedHandle = treesitter.syntaxMap.onParsed.subscribe proc() =
      self.scheduleUpdate()

    self.scheduleUpdate()

  proc doUpdate(self: ContextLineComponent) =
    let editor = self.owner.DocumentEditor
    let document = editor.currentDocument
    if document.isNil:
      self.contextLines.setLen(0)
      return

    let edit = editor.getTextEditorComponent().getOr:
      return
    let cursor = edit.selection.b

    if cursor == self.currentCursor:
      return

    self.currentCursor = cursor

    proc updateTaskBody(self: ContextLineComponent) {.async.} =
      let entries = await self.updateContextLines(cursor)
      self.contextLines = entries
      self.owner.DocumentEditor.markDirty()

    asyncSpawn updateTaskBody(self)

  proc newContextLineComponent*(settings: ContextLineSettings): ContextLineComponent =
    result = ContextLineComponent(
      typeId: ContextLineComponentId,
      settings: settings,
      currentCursor: point(-1, -1),
    )

    result.initializeImpl = (proc(self: Component, owner: ComponentOwner) =
      let self = self.ContextLineComponent
      let editor = owner.DocumentEditor

      self.updateTask = startDelayedPaused(1, false):
        self.doUpdate()

      self.documentChangedHandle = editor.onDocumentChanged.subscribe proc(arg: auto) =
        self.handleDocumentChanged(arg.old, editor.currentDocument)

      let edit = editor.getTextEditorComponent()
      if edit.isSome:
        self.selectionChangedHandle = edit.get.onSelectionsChanged2.subscribe proc(arg: auto) =
          self.scheduleUpdate()

      if editor.currentDocument.isNotNil:
        self.handleDocumentChanged(nil, editor.currentDocument)
    )

  proc init_module_contextline_component*() {.cdecl, exportc, dynlib.} =
    discard
