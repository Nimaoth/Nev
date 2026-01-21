import std/[options]
import misc/event
import component
import text/language/[language_server_base]
export component

include dynlib_export

type LanguageServerComponent* = ref object of Component
  onLanguageServerAttached*: Event[tuple[component: LanguageServerComponent, languageServer: LanguageServer]]
  onLanguageServerDetached*: Event[tuple[component: LanguageServerComponent, languageServer: LanguageServer]]

# DLL API
var LanguageServerComponentId* {.apprtl.}: ComponentTypeId

proc languageServerComponentAddLanguageServer*(self: LanguageServerComponent, languageServer: LanguageServer): bool {.apprtl, gcsafe, raises: [].}
proc languageServerComponentRemoveLanguageServer*(self: LanguageServerComponent, languageServer: LanguageServer): bool {.apprtl, gcsafe, raises: [].}
proc languageServerComponentHasLanguageServer*(self: LanguageServerComponent, languageServer: LanguageServer): bool {.apprtl, gcsafe, raises: [].}
proc getLanguageServerComponent*(self: ComponentOwner): Option[LanguageServerComponent] {.apprtl, gcsafe, raises: [].}

# Nice wrappers
proc addLanguageServer*(self: LanguageServerComponent, languageServer: LanguageServer): bool = languageServerComponentAddLanguageServer(self, languageServer)
proc removeLanguageServer*(self: LanguageServerComponent, languageServer: LanguageServer): bool = languageServerComponentRemoveLanguageServer(self, languageServer)

proc hasLanguageServer*(self: LanguageServerComponent, languageServer: LanguageServer): bool = languageServerComponentHasLanguageServer(self, languageServer)

# Implementation
when implModule:
  import std/strformat
  import misc/[util]
  import language_server_list

  LanguageServerComponentId = componentGenerateTypeId()

  type LanguageServerComponentImpl* = ref object of LanguageServerComponent
    languageServerList*: LanguageServerList

  proc languageServerComponentAddLanguageServer*(self: LanguageServerComponent, languageServer: LanguageServer): bool =
    let self = self.LanguageServerComponentImpl
    if not self.languageServerList.addLanguageServer(languageServer):
      return false
    self.onLanguageServerAttached.invoke (self.LanguageServerComponent, languageServer)
    return true

  proc languageServerComponentRemoveLanguageServer*(self: LanguageServerComponent, languageServer: LanguageServer): bool =
    let self = self.LanguageServerComponentImpl
    if not self.languageServerList.removeLanguageServer(languageServer):
      return false
    self.onLanguageServerDetached.invoke (self.LanguageServerComponent, languageServer)
    return true

  proc languageServerComponentHasLanguageServer*(self: LanguageServerComponent, languageServer: LanguageServer): bool =
    let self = self.LanguageServerComponentImpl
    return self.languageServerList.languageServers.find(languageServer) != -1

  proc getLanguageServerComponent*(self: ComponentOwner): Option[LanguageServerComponent] {.gcsafe, raises: [].} =
    return self.getComponent(LanguageServerComponentId).mapIt(it.LanguageServerComponent)

  proc newLanguageServerComponent*(languageServer: LanguageServerList): LanguageServerComponent =
    return LanguageServerComponentImpl(typeId: LanguageServerComponentId, languageServerList: languageServer)
