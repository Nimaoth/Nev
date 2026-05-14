#use input_handler theme treesitter lisp
import misc/[custom_async, custom_unicode, rope_utils]
import nimsumtree/[arc, rope]
import document_editor, vfs

import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor

from language_server import WorkspaceEdit

const currentSourcePath2 = currentSourcePath()
include module_base

proc workspaceEditApplyWorkspaceEdit(editors: DocumentEditorService, vfs: VFS, wsEdit: WorkspaceEdit): Future[bool] {.rtl, async: (raises: []).}

proc applyWorkspaceEdit*(editors: DocumentEditorService, vfs: VFS, wsEdit: WorkspaceEdit): Future[bool] {.async: (raises: []).} = workspaceEditApplyWorkspaceEdit(editors, vfs, wsEdit).await

proc runeCursorToCursor*(rope: Rope, cursor: RuneCursor): Cursor =
  if cursor.line < 0:
    return (0, 0)

  if cursor.line >= rope.lines:
    return rope.endPoint.toCursor

  return (cursor.line, rope.byteOffsetInLine(cursor.line, cursor.column))

proc runeSelectionToSelection*(rope: Rope, cursor: RuneSelection): Selection =
  return (rope.runeCursorToCursor(cursor.first), rope.runeCursorToCursor(cursor.last))

proc lspRangeToSelection*(rope: Rope, r: language_server.Range): Selection =
  let runeSelection = (
    (r.start.line, r.start.character.RuneIndex),
    (r.`end`.line, r.`end`.character.RuneIndex))
  return rope.runeSelectionToSelection(runeSelection)

when implModule:
  import std/[options, json, tables, uri]
  import misc/[util, custom_logger, myjsonutils]
  import document, service, vfs_service

  import text_component

  logCategory "workspace-edit"

  proc workspaceEditApplyWorkspaceEdit(editors: DocumentEditorService, vfs: VFS, wsEdit: WorkspaceEdit): Future[bool] {.async: (raises: []).} =
    let editors = if editors != nil:
      editors
    else:
      ({.gcsafe.}: getServices()).getServiceChecked(DocumentEditorService)
    let vfs = if not vfs.isNil:
      vfs
    else:
      ({.gcsafe.}: getServices()).getServiceChecked(VFSService).vfs

    proc lspPathToVfsPath(self: VFS, lspPath: string): string =
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

      var queue = newSeq[tuple[doc: Document, edits: seq[language_server.LspTextEdit]]]()
      for lspPath, editJson in changes.fields.pairs:
        if not documents.contains(lspPath):
          continue

        let doc = documents[lspPath]
        try:
          let edits = editJson.jsonTo(seq[language_server.LspTextEdit])
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
        asyncSpawn doc.save()

      return true

    return false

  proc init_module_workspace_edit*() {.cdecl, exportc, dynlib.} =
    discard
