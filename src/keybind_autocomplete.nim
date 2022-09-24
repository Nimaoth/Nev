import std/[strutils, logging]
import input, document_editor, events

var logger = newConsoleLogger()

type KeybindAutocompletion* = ref object of DocumentEditor
  discard

method getEventHandlers*(self: KeybindAutocompletion): seq[EventHandler] =
  return @[self.eventHandler]

proc handleAction(self: KeybindAutocompletion, action: string, arg: string): EventResponse =
  # echo "handleAction ", action, " '", arg, "'"
  case action
  of "cursor.up": discard
  of "cursor.down": discard
  else:
    logger.log(lvlError, "[KeybindAutocomplete] Unknown action '$1 $2'" % [action, arg])
  return Handled

proc handleInput(self: KeybindAutocompletion, input: string): EventResponse =
  return Handled

proc newKeybindAutocompletion*(): DocumentEditor =
  let editor = KeybindAutocompletion(eventHandler: nil)
  editor.eventHandler = eventHandler2:
    command "<UP>", "cursor.up"
    command "<DOWN>", "cursor.down"
    onAction:
      editor.handleAction action, arg
    onInput:
      editor.handleInput input
  return editor