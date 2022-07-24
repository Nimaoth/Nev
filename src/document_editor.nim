import std/[strformat, strutils, algorithm, math, logging, unicode]
import input, document, events


type DocumentEditor* = ref object of RootObj
  eventHandler*: EventHandler

type AstDocumentEditor* = ref object of DocumentEditor
  document*: AstDocument

method canEdit*(self: DocumentEditor, document: Document): bool {.base.} =
  return false

method canEdit*(self: AstDocumentEditor, document: Document): bool =
  if document of AstDocument: return true
  else: return false

method createWithDocument*(self: DocumentEditor, document: Document): DocumentEditor {.base.} =
  return nil

method createWithDocument*(self: AstDocumentEditor, document: Document): DocumentEditor =
  let handler = eventHandler2:
    # command "rt", "xvlc"
    onAction:
      Handled
    onInput:
      Handled
  return AstDocumentEditor(eventHandler: handler, document: AstDocument(document))

method getEventHandlers*(self: DocumentEditor): seq[EventHandler] {.base.} =
  return @[]