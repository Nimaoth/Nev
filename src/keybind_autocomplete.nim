import document_editor, input_handler

type KeybindAutocompletion* = ref object of DocumentEditor
  discard

method getEventHandlers*(self: KeybindAutocompletion): seq[EventHandler] =
  return @[self.eventHandler]

proc newKeybindAutocompletion*(): DocumentEditor =
  result = KeybindAutocompletion()
  result.init()