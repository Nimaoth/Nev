import std/[strutils, sequtils, sugar, options, json, streams, strformat, tables, deques, sets, algorithm, os, uri]
import misc/[id, util, rect_utils, event, custom_logger, custom_async, fuzzy_matching,
  custom_unicode, delayed_task, myjsonutils, regex, timer, response, rope_utils, rope_regex, jsonex]
import document, document_editor, events, vmath, bumpy, input, custom_treesitter, indent, snippet
import config_provider, service, layout, platform_service, vfs, vfs_service, command_service, toast

from language/lsp_types import CompletionList, CompletionItem, InsertTextFormat,
  TextEdit, Position, asTextEdit, asInsertReplaceEdit, toJsonHook, CodeAction, CodeActionResponse, CodeActionKind,
  Command, WorkspaceEdit, asCommand, asCodeAction

import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor

logCategory "workspace-edit"

proc applyWorkspaceEdit*(editors: DocumentEditorService, vfs: VFS, wsEdit: WorkspaceEdit): Future[bool] {.async: (raises: []).}

import text_document, text_editor
import service

proc applyWorkspaceEdit*(editors: DocumentEditorService, vfs: VFS, wsEdit: WorkspaceEdit): Future[bool] {.async: (raises: []).} =
  let editors = if editors != nil:
    editors
  else:
    ({.gcsafe.}: gServices).getService(DocumentEditorService).get
  let vfs = if vfs != nil:
    vfs
  else:
    ({.gcsafe.}: gServices).getService(VFSService).get.vfs

  proc lspPathToVfsPath(self: VFS, lspPath: string): string =
    let localVfs = self.getVFS("local://").vfs # todo
    let localPath = lspPath.decodeUrl.parseUri.path.normalizePathUnix
    return localVfs.normalize(localPath)

  log lvlInfo, "Apply workspace edit {wsEdit}"
  if wsEdit.changes.getSome(changes):
    if changes.kind != JObject:
      return false

    var documents = initTable[string, TextDocument]()
    for lspPath, editJson in changes.fields.pairs:
      let filename = vfs.lspPathToVfsPath(lspPath)
      if editors.getOrOpenDocument(filename).getSome(doc) and doc of TextDocument:
        documents[lspPath] = doc.TextDocument
      else:
        log lvlError, "Failed to apply workspace edit, file not found or not a text document: '" & filename & "'"
        return false

    for doc in documents.values:
      if doc.requiresLoad:
        doc.load()

    var queue = newSeq[tuple[doc: TextDocument, edits: seq[lsp_types.TextEdit]]]()
    for lspPath, editJson in changes.fields.pairs:
      let filename = vfs.lspPathToVfsPath(lspPath)
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
        log lvlDebug, "doc '" & doc.filename & "' is still loading"
        try:
          await sleepAsync(1.milliseconds)
        except:
          discard
        continue

      var selections = newSeq[Selection]()
      var texts = newSeq[string]()
      for edit in edits:
        selections.add(doc.lspRangeToSelection(edit.range))
        texts.add(edit.newText)

      for ed in editors.getEditorsForDocument(doc):
        if ed of text_editor.TextDocumentEditor:
          let textEditor = text_editor.TextDocumentEditor(ed)
          textEditor.addNextCheckpoint("insert")

      discard doc.edit(selections, @[], texts)

      for ed in editors.getEditorsForDocument(doc):
        if ed of text_editor.TextDocumentEditor:
          let textEditor = text_editor.TextDocumentEditor(ed)
          textEditor.setDefaultMode()

    return true

  return false
