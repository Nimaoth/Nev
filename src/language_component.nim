import std/[options]
import misc/[event, util]
import component

export component

include dynlib_export

type LanguageComponent* = ref object of Component
  mLanguageId: string
  onLanguageChanged*: Event[LanguageComponent]

var LanguageComponentId* {.apprtlvar.}: ComponentTypeId

# DLL API
{.push apprtl, gcsafe, raises: [].}
proc newLanguageComponent*(languageId: string = ""): LanguageComponent
proc languageComponentLanguageId*(self: LanguageComponent): string
proc languageComponentSetLanguageId*(self: LanguageComponent, languageId: string)
{.pop.}

# Nice wrappers
proc languageId*(self: LanguageComponent): string {.inline.} = self.languageComponentLanguageId()
proc setLanguageId*(self: LanguageComponent, languageId: string) {.inline.} = self.languageComponentSetLanguageId(languageId)

proc getLanguageComponent*(self: ComponentOwner): Option[LanguageComponent] {.gcsafe, raises: [].} =
  return self.getComponent(LanguageComponentId).mapIt(it.LanguageComponent)

# Implementation
when implModule:
  LanguageComponentId = componentGenerateTypeId()

  proc languageComponentLanguageId*(self: LanguageComponent): string {.gcsafe, raises: [].} =
    self.mLanguageId

  proc languageComponentSetLanguageId*(self: LanguageComponent, languageId: string) {.gcsafe, raises: [].} =
    if self.mLanguageId == languageId:
      return
    self.mLanguageId = languageId
    self.onLanguageChanged.invoke(self)

  proc newLanguageComponent*(languageId: string = ""): LanguageComponent =
    return LanguageComponent(typeId: LanguageComponentId, mLanguageId: languageId)
