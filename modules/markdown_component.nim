
import std/[options]
import chroma
import nimsumtree/rope
import misc/[event, myjsonutils]
import config_provider
import component

export component

const currentSourcePath2 = currentSourcePath()
include module_base

# Implementation
when implModule:
  import std/[tables]
  import nimsumtree/[buffer, sumtree]
  import misc/[util, custom_logger, rope_utils, delayed_task, custom_async, arena, array_view, id]
  import text/[display_map, overlay_map, syntax_map, treesitter_types, treesitter_type_conv, custom_treesitter]
  import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
  import service, event_service, document_editor, document, decoration_component, treesitter_component, text_component, language_component

  logCategory "decoration-component"

  let MarkdownComponentId = componentGenerateTypeId()

  type MarkdownComponent* = ref object of Component
    updateTask: DelayedTask
    documentChangedHandle: Id
    editHandle: Id
    languageChangedHandle: Id
    parsedHandle: Id

  proc getMarkdownComponent*(self: ComponentOwner): Option[MarkdownComponent] {.gcsafe, raises: [].} =
    return self.getComponent(MarkdownComponentId).mapIt(it.MarkdownComponent)

  proc updateAsync(self: MarkdownComponent): Future[void] {.async.} =
    let editor = self.owner.DocumentEditor
    if editor.currentDocument.isNil:
      return
    let decorations = editor.getDecorationComponent().getOr:
      return
    let treesitter = editor.currentDocument.getTreesitterComponent().getOr:
      return
    # if treesitter.tsLanguage.isNil or treesitter.tsLanguage.languageId != "markdown":
    #   return

    let text = editor.currentDocument.getTextComponent().getOr:
      return

    let content = text.content
    let fullRange = (point(0, 0)...content.endPoint).tsRange

    template checkRes(b: untyped): untyped =
      if not b:
        return

    let language = getLoadedLanguage("markdown")
    if language.isNil:
      return

    let tableQuery = await language.query("markdown_table", "(pipe_table) @table")
    if tableQuery.isNone or self.owner.isNil or editor.isNil or editor.currentDocument.isNil:
      return

    let syntaxMap = treesitter.syntaxMap.snapshot
    if syntaxMap.layerIndex.isNil:
      return

    decorations.clearOverlays(7)

    var cursor = syntaxMap.layerIndex.initCursor(SyntaxLayerRefSummary)
    cursor.next()
    while cursor.item.getSome(item):
      defer:
        cursor.next()
      if item.depth > 0 and item.index == 0:
        continue
      let layer {.cursor.} = syntaxMap.layers[item.index]
      if layer.language != "markdown":
        continue

      var arena = initArena(16 * 1024)
      for match in tableQuery.get.matches(layer.tree.root, fullRange, arena):
        var langName = ""
        for capture in match.captures:
          capture.node.withTreeCursor(c):
            var node = c.currentNode
            checkRes c.gotoFirstChild()

            type Cell = object
              node: TSNode
              width: int
              text: string
              range: Range[Point]
              isDelimiter: bool

            var rows: seq[seq[Cell]] = @[]
            var row: seq[Cell] = @[]
            var maxWidths: seq[int] = @[]

            while true:
              node = c.currentNode

              proc parseRow(c: var TSTreeCursor, offset: int, isDelimiter: bool): seq[Cell] =
                var cellStartColumn = 0
                if c.gotoFirstChild():
                  defer:
                    discard c.gotoParent()
                  while true:
                    let node = c.currentNode
                    let r = node.getRange.toRange
                    if node.isNamed:
                      result.add Cell(node: node, width: r.b.column.int - cellStartColumn + offset, text: $content[r], range: r, isDelimiter: isDelimiter)
                    else:
                      cellStartColumn = r.b.column.int
                    if not c.gotoNextSibling():
                      break

              case node.nodeType
              of "pipe_table_header":
                rows.add c.parseRow(0, false)
              of "pipe_table_delimiter_row":
                rows.add c.parseRow(1, true)
              of "pipe_table_row":
                rows.add c.parseRow(0, false)
              else:
                discard

              if not c.gotoNextSibling():
                break

            for column in 0..int.high:
              var maxWidth = -1
              for row in rows:
                if column >= row.len:
                  continue
                maxWidth = max(maxWidth, row[column].width)
              if maxWidth < 0:
                break
              maxWidths.add(maxWidth)

            for row in rows.mitems:
              for i, cell in row:
                let overlayWidth = maxWidths[i] - cell.width
                if overlayWidth > 0:
                  let ch = if cell.isDelimiter: "-" else: " "
                  let text = ch.repeat(overlayWidth)
                  decorations.addOverlay(cell.range.b...cell.range.b, text, 7, "comment", Bias.Right)

  proc update(self: MarkdownComponent) =
    asyncSpawn self.updateAsync()

  proc handleDocumentChanged(self: MarkdownComponent, old: Document, new: Document) =
    if old != nil:
      if self.editHandle != idNone() and old.getTextComponent().getSome(text):
        text.onEdit.unsubscribe(self.editHandle)
        self.editHandle = idNone()
      if self.languageChangedHandle != idNone() and old.getLanguageComponent().getSome(language):
        language.onLanguageChanged.unsubscribe(self.languageChangedHandle)
        self.languageChangedHandle = idNone()
      if self.parsedHandle != idNone() and old.getTreesitterComponent().getSome(treesitter):
        treesitter.syntaxMap.onParsed.unsubscribe(self.parsedHandle)
        self.parsedHandle = idNone()
    if new.isNil:
      return
    let text = new.getTextComponent().getOr:
      return
    let language = new.getLanguageComponent().getOr:
      return
    let treesitter = new.getTreesitterComponent().getOr:
      return
    self.editHandle = text.onEdit.subscribe proc(p: Patch[Point]) =
      if self.updateTask.isNotNil:
        self.updateTask.schedule()
    self.languageChangedHandle = language.onLanguageChanged.subscribe proc(l: LanguageComponent) =
      if self.updateTask.isNotNil:
        self.updateTask.schedule()
    self.parsedHandle = treesitter.syntaxMap.onParsed.subscribe proc() =
      if self.updateTask.isNotNil:
        self.updateTask.schedule()
    if self.updateTask.isNotNil:
      self.updateTask.schedule()

  proc newMarkdownComponent*(editor: DocumentEditor): MarkdownComponent =
    var res = MarkdownComponent(
      typeId: MarkdownComponentId,
    )
    res.updateTask = startDelayedPaused(1, false):
      res.update()

    res.documentChangedHandle = editor.onDocumentChanged.subscribe proc(arg: auto) {.closure, gcsafe, raises: [].} = res.handleDocumentChanged(arg.old, editor.currentDocument)
    if editor.currentDocument.isNotNil:
      res.handleDocumentChanged(nil, editor.currentDocument)

    return res

  proc init_module_markdown_component*() {.cdecl, exportc, dynlib.} =
    let services = getServices()
    if services == nil:
      log lvlWarn, &"Failed to initialize init_module_markdown_component: no services found"
      return

    let events = services.getService(EventService)
    let documents = services.getService(DocumentEditorService).get

    proc handleEditorRegistered(event, payload: string) {.gcsafe, raises: [].} =
      try:
        let id = payload.parseInt.EditorIdNew
        if documents.getEditor(id).getSome(editor):
          let md = editor.getMarkdownComponent()
          if md.isNone:
            editor.addComponent(newMarkdownComponent(editor))
      except CatchableError as e:
        log lvlError, &"Error: {e.msg}"
    events.get.listen(newId(), "editor/*/registered", handleEditorRegistered)
