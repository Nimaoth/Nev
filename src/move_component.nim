import std/[tables, hashes, options]
import misc/event
import component
import text/language/[language_server_base]
import nimsumtree/[rope]

export component

include dynlib_export

type MoveComponent* = ref object of Component

# DLL API
var MoveComponentId* {.apprtl.}: ComponentTypeId

proc moveComponentApplyMove*(self: MoveComponent, selections: openArray[Range[Point]], move: string, count: int = 0, includeEol: bool = true, wrap: bool = true, options: JsonNode = nil): seq[Range[Point]] {.apprtl.}

# Nice wrappers
proc applyMove*(self: MoveComponent, selections: openArray[Range[Point]], move: string, count: int = 0, includeEol: bool = true, wrap: bool = true, options: JsonNode = nil): seq[Range[Point]] {.inline.} = textDocumentApplyMove(self, selections, move, count, includeEol, wrap, options)

# Implementation
when implModule:
  import std/strformat
  import misc/[util]
  import move_database, service

  MoveComponentId = componentGenerateTypeId()

  type MoveComponentImpl* = ref object of MoveComponent
    moveDatabase*: MoveDatabase

  proc languageServerComponentAddLanguageServer*(self: MoveComponent, languageServer: LanguageServer): bool =
    let self = self.MoveComponentImpl
    if not self.languageServerList.addLanguageServer(languageServer):
      return false
    self.onLanguageServerAttached.invoke (self.MoveComponent, languageServer)
    return true

  proc getMoveComponent*(self: ComponentOwner): Option[MoveComponent] {.gcsafe, raises: [].} =
    return self.getComponent(MoveComponentId).mapIt(it.MoveComponent)

  proc getMoveComponentChecked*(self: ComponentOwner): MoveComponent {.gcsafe, raises: [].} =
    return self.getComponent(MoveComponentId).mapIt(it.MoveComponent).get

  proc newMoveComponent*(services: Services): MoveComponent =
    return MoveComponentImpl(moveDatabase: services.getServiceChecked(MoveDatabase))

proc moveComponentApplyMove*(self: MoveComponent, selections: openArray[Range[Point]], move: string, count: int = 0, includeEol: bool = true, wrap: bool = true, options: JsonNode = nil): seq[Range[Point]] =
