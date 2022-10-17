import std/[strutils, logging, sequtils]
import input, document_editor, events

var logger = newConsoleLogger()

type KeybindAutocompletion* = ref object of DocumentEditor
  discard

method getEventHandlers*(self: KeybindAutocompletion): seq[EventHandler] =
  return @[self.eventHandler]

proc handleAction(self: KeybindAutocompletion, action: string, arg: string): EventResponse =
  return Ignored

proc handleInput(self: KeybindAutocompletion, input: string): EventResponse =
  return Ignored

proc newKeybindAutocompletion*(): DocumentEditor =
  return KeybindAutocompletion()