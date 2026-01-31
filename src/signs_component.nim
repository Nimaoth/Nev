import std/[options]
import chroma
import misc/[event]
import config_provider
import component

export component

include dynlib_export

type
  SignColumnShowKind* {.pure.} = enum Auto = "auto", Yes = "yes", No = "no", Number = "number"

proc typeNameToJson*(T: typedesc[SignColumnShowKind]): string =
  return "\"auto\" | \"yes\" | \"no\" | \"number\""

declareSettings SignColumnSettings, "":
  ## Defines how the sign column is displayed.
  ## - auto: Signs are next to line numbers, width is based on amount of signs in a line.
  ## - yes: Signs are next to line numbers and sign column is always visible. Width is defined in `max-width`
  ## - no: Don't show the sign column
  ## - number: Show signs instead of the line number, no extra sign column.
  declare show, SignColumnShowKind, SignColumnShowKind.Number

  ## If `show` is `auto` then this is the max width of the sign column, if `show` is `yes` then this is the exact width.
  declare maxWidth, Option[int], 2

type SignsComponent* = ref object of Component
  settings*: SignColumnSettings

# DLL API
var SignsComponentId* {.apprtl.}: ComponentTypeId

proc signsComponentClearSigns(self: SignsComponent, group: string = "") {.apprtl, gcsafe, raises: [].}
proc signsComponentAddSign(self: SignsComponent, id: Id, line: int, text: string, group: string = "", tint: Color = color(1, 1, 1), color: string = "", width: int = 1): Id {.apprtl, gcsafe, raises: [].}

proc getSignsComponent*(self: ComponentOwner): Option[SignsComponent] {.apprtl, gcsafe, raises: [].}

# Nice wrappers
proc clearSigns*(self: SignsComponent, group: string = "") {.inline.} = signsComponentClearSigns(self, group)
proc addSign*(self: SignsComponent, id: Id, line: int, text: string, group: string = "", tint: Color = color(1, 1, 1), color: string = "", width: int = 1): Id {.inline.} = signsComponentAddSign(self, id, line, text, group, tint, color, width)

# Implementation
when implModule:
  import std/[tables]
  import misc/[util, custom_logger]
  import nimsumtree/rope
  import document_editor

  logCategory "signs-component"

  SignsComponentId = componentGenerateTypeId()

  type SignsComponentImpl* = ref object of SignsComponent
    signs*: Table[int, seq[tuple[id: Id, group: string, text: string, tint: Color, color: string, width: int]]]

  proc getSignsComponent*(self: ComponentOwner): Option[SignsComponent] {.gcsafe, raises: [].} =
    return self.getComponent(SignsComponentId).mapIt(it.SignsComponent)

  proc newSignsComponent*(settings: SignColumnSettings): SignsComponentImpl =
    return SignsComponentImpl(
      typeId: SignsComponentId,
      settings: settings,
    )

  proc clear*(self: SignsComponent) =
    let self = self.SignsComponentImpl
    self.signs.clear()

  proc signsComponentClearSigns(self: SignsComponent, group: string = "") =
    let self = self.SignsComponentImpl
    var linesToRemove: seq[int] = @[]
    for line, signs in self.signs.mpairs:
      for i in countdown(signs.high, 0):
        if signs[i].group == group:
          signs.removeSwap(i)
      if signs.len == 0:
        linesToRemove.add line

    for line in linesToRemove:
      self.signs.del line

    self.owner.DocumentEditor.markDirty()

  proc signsComponentAddSign(self: SignsComponent, id: Id, line: int, text: string, group: string = "",
      tint: Color = color(1, 1, 1), color: string = "", width: int = 1): Id =
    let self = self.SignsComponentImpl
    self.signs.withValue(line, val):
      val[].add (id, group, text, tint, color, width)
    do:
      self.signs[line] = @[(id, group, text, tint, color, width)]
    self.owner.DocumentEditor.markDirty()

  proc requiredSignColumnWidth*(self: SignsComponentImpl, visibleLines: Range[int]): int =
    case self.settings.show.get()
    of SignColumnShowKind.Auto:
      var width = 0
      for line in visibleLines.a..visibleLines.b:
        self.signs.withValue(line, value):
          var subWidth = 0
          for s in value[]:
            subWidth += s.width
          width = max(width, subWidth)

      if self.settings.maxWidth.get().getSome(maxWidth):
        width = min(width, maxWidth)
      return width

    of SignColumnShowKind.Yes:
      if self.settings.maxWidth.get().getSome(maxWidth):
        return maxWidth
      return 1

    of SignColumnShowKind.No:
      return 0

    of SignColumnShowKind.Number:
      return 0
