import std/[strformat, strutils, algorithm, math, logging, unicode]
import input, document, events


type DocumentEditor* = ref object of RootObj
  eventHandler*: EventHandler
  renderHeader*: bool
  fillAvailableSpace*: bool

proc init*(self: DocumentEditor) =
  self.renderHeader = true
  self.fillAvailableSpace = true

method canEdit*(self: DocumentEditor, document: Document): bool {.base.} =
  return false

method createWithDocument*(self: DocumentEditor, document: Document): DocumentEditor {.base.} =
  return nil

method getEventHandlers*(self: DocumentEditor): seq[EventHandler] {.base.} =
  return @[]

method handleDocumentChanged*(self: DocumentEditor) {.base.} =
  discard