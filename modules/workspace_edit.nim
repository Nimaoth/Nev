import misc/[custom_async]
import nimsumtree/[arc]
import document_editor, vfs

from text/language/lsp_types import WorkspaceEdit

const currentSourcePath2 = currentSourcePath()
include module_base

proc workspaceEditApplyWorkspaceEdit(editors: DocumentEditorService, vfs: Arc[VFS2], wsEdit: WorkspaceEdit): Future[bool] {.rtl, async: (raises: []).}

proc applyWorkspaceEdit*(editors: DocumentEditorService, vfs: Arc[VFS2], wsEdit: WorkspaceEdit): Future[bool] {.async: (raises: []).} = workspaceEditApplyWorkspaceEdit(editors, vfs, wsEdit).await

when implModule:
  import std/[options, json, tables, uri]
  import misc/[util, custom_logger, custom_unicode, myjsonutils, rope_utils]
  import nimsumtree/[rope]
  import document, service, vfs_service

  import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor

  import text_component

  logCategory "workspace-edit"

  proc runeCursorToCursor*(rope: Rope, cursor: RuneCursor): Cursor =
    if cursor.line < 0 or cursor.line > rope.lines - 1:
      return (0, 0)

    return (cursor.line, rope.byteOffsetInLine(cursor.line, cursor.column))

  proc runeSelectionToSelection*(rope: Rope, cursor: RuneSelection): Selection =
    return (rope.runeCursorToCursor(cursor.first), rope.runeCursorToCursor(cursor.last))

  proc lspRangeToSelection*(rope: Rope, r: lsp_types.Range): Selection =
    let runeSelection = (
      (r.start.line, r.start.character.RuneIndex),
      (r.`end`.line, r.`end`.character.RuneIndex))
    return rope.runeSelectionToSelection(runeSelection)

  proc workspaceEditApplyWorkspaceEdit(editors: DocumentEditorService, vfs: Arc[VFS2], wsEdit: WorkspaceEdit): Future[bool] {.async: (raises: []).} =
    let editors = if editors != nil:
      editors
    else:
      ({.gcsafe.}: getServices()).getService(DocumentEditorService).get
    let vfs = if not vfs.isNil:
      vfs
    else:
      ({.gcsafe.}: getServices()).getService(VFSService).get.vfs2

    proc lspPathToVfsPath(self: Arc[VFS2], lspPath: string): string =
      let localVfs = self.getVFS("local://").vfs # todo
      let localPath = lspPath.decodeUrl.parseUri.path.normalizePathUnix
      return localVfs.normalize(localPath)

    log lvlInfo, "Apply workspace edit {wsEdit}"
    if wsEdit.changes.getSome(changes):
      if changes.kind != JObject:
        return false

      var documents = initTable[string, Document]()
      for lspPath, editJson in changes.fields.pairs:
        let filename = vfs.lspPathToVfsPath(lspPath)
        if editors.getOrOpenDocument(filename).getSome(doc):
          documents[lspPath] = doc
        else:
          log lvlError, "Failed to apply workspace edit, file not found or not a text document: '" & filename & "'"
          return false

      for doc in documents.values:
        if doc.requiresLoad:
          doc.load()

      var queue = newSeq[tuple[doc: Document, edits: seq[lsp_types.TextEdit]]]()
      for lspPath, editJson in changes.fields.pairs:
        if not documents.contains(lspPath):
          continue

        let doc = documents[lspPath]
        try:
          let edits = editJson.jsonTo(seq[lsp_types.TextEdit])
          queue.add (doc, edits)
        except:
          log lvlError, "Failed to parse text edit: " & $editJson

      while queue.len > 0:
        let (doc, edits) = queue[0]
        queue.removeShift(0)
        if doc.requiresLoad or doc.isLoadingAsync:
          queue.add (doc, edits)

          try:
            await sleepAsync(1.milliseconds)
          except:
            discard
          continue

        let text = doc.getTextComponent().getOr:
          continue

        var selections = newSeq[Range[Point]]()
        var texts = newSeq[string]()
        for edit in edits:
          selections.add(text.content.lspRangeToSelection(edit.range).toRange)
          texts.add(edit.newText)

        discard text.edit(selections, @[], texts, checkpoint = "insert")
        doc.save()

      return true

    return false

  proc init_module_workspace_edit*() {.cdecl, exportc, dynlib.} =
    discard
