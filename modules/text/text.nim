#use text_editor_component formatting_component layout stats hover_component command_component snippet_component contextline_component workspace_edit search_component treesitter_component register

const currentSourcePath2 = currentSourcePath()
include module_base

# DLL API

# Nice wrappers

# Implementation
when implModule:
  import std/[options]
  import misc/[jsonex, id]
  import text_editor, text_document, service, document_editor

  proc init_module_text*() {.cdecl, exportc, dynlib.} =
    let editors = getServiceChecked(DocumentEditorService)
    editors.addDocumentFactory(TextDocumentFactory(
      kind: "text",
      canOpenFileImpl: proc(self: DocumentFactory, path: string): bool {.gcsafe, raises: [].} = canOpenFile(self.TextDocumentFactory, path),
      createDocumentImpl: proc(self: DocumentFactory, services: Services, path: string, load: bool, options: JsonNodeEx = nil, id = Id.none): Document {.gcsafe, raises: [].} = createDocument(self.TextDocumentFactory, services, path, load, options, id),
    ))
    editors.addDocumentEditorFactory(TextDocumentEditorFactory(
      canEditDocumentImpl: proc(self: DocumentEditorFactory, document: Document, options: JsonNodeEx = nil): bool {.gcsafe, raises: [].} = canEditDocument(self.TextDocumentEditorFactory, document, options),
      createEditorImpl: proc(self: DocumentEditorFactory, services: Services, document: Document, options: JsonNodeEx = nil): DocumentEditor {.gcsafe, raises: [].} = createEditor(self.TextDocumentEditorFactory, services, document, options),
    ))
    registerTextEditorCommands()
