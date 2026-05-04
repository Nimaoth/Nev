import std/[options, tables]
import chroma, vmath
import nimsumtree/rope
import misc/[event, myjsonutils, render_command, generational_seq]
import text/[display_map, overlay_map]
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
import config_provider
import component

export component

const currentSourcePath2 = currentSourcePath()
include module_base

type
  CustomOverlayRenderer* = proc(id: int, size: Vec2, localOffset: int, commands: var RenderCommands): Vec2 {.gcsafe, raises: [].}
  CustomRendererId* = distinct uint64

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
  declare maxWidth, int, 2

type
  OverlayRenderLocation* {.pure.} = enum
    Inline
    Below
    Above
  DecorationComponent* = ref object of Component
    settings*: SignColumnSettings
    signs*: Table[int, seq[tuple[id: Id, group: string, text: string, tint: Color, color: string, width: int]]]
    customHighlights*: Table[int, seq[tuple[id: Id, selection: Selection, color: string, tint: Color]]]
    customOverlayRenderers*: GenerationalSeq[CustomOverlayRenderer, CustomRendererId]

  OverlayDef* = tuple[range: Range[Point], text: string, scope: string = "", bias: Bias = Bias.Left, renderId: int = 0, location: OverlayRenderLocation = OverlayRenderLocation.Inline]

# DLL API

{.push modrtl, gcsafe, raises: [].}
proc newDecorationComponent*(settings: SignColumnSettings, displayMap: DisplayMap): DecorationComponent
proc decorationComponentClearSigns(self: DecorationComponent, group: string = "")
proc decorationComponentAddSign(self: DecorationComponent, id: Id, line: int, text: string, group: string = "", tint: Color = color(1, 1, 1), color: string = "", width: int = 1): Id
proc decorationComponentClearCustomHighlights(self: DecorationComponent, id: Id)
proc decorationComponentAddCustomHighlight(self: DecorationComponent, id: Id, selection: Range[Point], color: string, tint: Color = color(1, 1, 1))
proc decorationComponentClearOverlays(self: DecorationComponent, id: int = -1)
proc decorationComponentAddOverlay(self: DecorationComponent, selection: Range[Point], text: string, id: int, scope: string, bias: Bias, renderId: int = 0, location: OverlayRenderLocation = OverlayRenderLocation.Inline)
proc decorationComponentAddOverlays(self: DecorationComponent, id: int, replace: bool, overlays: sink seq[OverlayDef])
proc decorationComponentAddCustomRenderer(self: DecorationComponent, impl: CustomOverlayRenderer): CustomRendererId
proc decorationComponentRemoveCustomRenderer(self: DecorationComponent, id: CustomRendererId)
proc decorationComponentAllocateOverlayId(self: DecorationComponent): Option[int]
proc decorationComponentReleaseOverlayId(self: DecorationComponent, id: int)
proc decorationComponentClear(self: DecorationComponent)
proc decorationComponentClearAllSigns(self: DecorationComponent)
proc decorationComponentClearHighlights(self: DecorationComponent)
proc decorationComponentRequiredSignColumnWidth(self: DecorationComponent, visibleLines: Range[int]): int

proc getDecorationComponent*(self: ComponentOwner): Option[DecorationComponent]
{.pop.}

# Nice wrappers
proc clearSigns*(self: DecorationComponent, group: string = "") {.inline.} = decorationComponentClearSigns(self, group)
proc clearAllSigns*(self: DecorationComponent) = decorationComponentClearAllSigns(self)
proc addSign*(self: DecorationComponent, id: Id, line: int, text: string, group: string = "", tint: Color = color(1, 1, 1), color: string = "", width: int = 1): Id {.inline.} = decorationComponentAddSign(self, id, line, text, group, tint, color, width)
proc clearCustomHighlights*(self: DecorationComponent, id: Id) {.inline.} = decorationComponentClearCustomHighlights(self, id)
proc clearHighlights*(self: DecorationComponent) = decorationComponentClearHighlights(self)
proc addCustomHighlight*(self: DecorationComponent, id: Id, selection: Range[Point], color: string, tint: Color = color(1, 1, 1)) {.inline.} = decorationComponentAddCustomHighlight(self, id, selection, color, tint)
proc clearOverlays*(self: DecorationComponent, id: int = -1) {.inline.} = decorationComponentClearOverlays(self, id)
proc addOverlay*(self: DecorationComponent, selection: Range[Point], text: string, id: int, scope: string, bias: Bias, renderId: int = 0, location: OverlayRenderLocation = OverlayRenderLocation.Inline) {.inline.} = decorationComponentAddOverlay(self, selection, text, id, scope, bias, renderId, location)
proc addOverlays*(self: DecorationComponent, id: int, replace: bool, overlays: sink seq[OverlayDef]) = decorationComponentAddOverlays(self, id, replace, overlays)
proc addCustomRenderer*(self: DecorationComponent, impl: CustomOverlayRenderer): CustomRendererId {.inline.} = decorationComponentAddCustomRenderer(self, impl)
proc removeCustomRenderer*(self: DecorationComponent, id: CustomRendererId) {.inline.} = decorationComponentRemoveCustomRenderer(self, id)
proc allocateOverlayId*(self: DecorationComponent): Option[int] {.inline.} = decorationComponentAllocateOverlayId(self)
proc releaseOverlayId*(self: DecorationComponent, id: int) {.inline.} = decorationComponentReleaseOverlayId(self, id)
proc clear*(self: DecorationComponent) = decorationComponentClear(self)
proc requiredSignColumnWidth*(self: DecorationComponent, visibleLines: Range[int]): int = decorationComponentRequiredSignColumnWidth(self, visibleLines)

# Implementation
when implModule:
  import std/[sequtils]
  import misc/[util, custom_logger, rope_utils]
  import document_editor

  logCategory "decoration-component"

  let DecorationComponentId = componentGenerateTypeId()

  type DecorationComponentImpl* = ref object of DecorationComponent
    displayMap: DisplayMap

  proc getDecorationComponent*(self: ComponentOwner): Option[DecorationComponent] {.gcsafe, raises: [].} =
    return self.getComponent(DecorationComponentId).mapIt(it.DecorationComponent)

  proc newDecorationComponent*(settings: SignColumnSettings, displayMap: DisplayMap): DecorationComponent =
    return DecorationComponentImpl(
      typeId: DecorationComponentId,
      settings: settings,
      displayMap: displayMap,
    )

  proc decorationComponentClear(self: DecorationComponent) =
    let self = self.DecorationComponentImpl
    self.signs.clear()
    self.customHighlights.clear()

  proc decorationComponentClearAllSigns(self: DecorationComponent) =
    let self = self.DecorationComponentImpl
    self.signs.clear()

  proc decorationComponentClearHighlights(self: DecorationComponent) =
    let self = self.DecorationComponentImpl
    self.customHighlights.clear()

  proc decorationComponentClearSigns(self: DecorationComponent, group: string = "") =
    let self = self.DecorationComponentImpl
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

  proc decorationComponentAddSign(self: DecorationComponent, id: Id, line: int, text: string, group: string = "",
      tint: Color = color(1, 1, 1), color: string = "", width: int = 1): Id =
    let self = self.DecorationComponentImpl
    self.signs.withValue(line, val):
      val[].add (id, group, text, tint, color, width)
    do:
      self.signs[line] = @[(id, group, text, tint, color, width)]
    self.owner.DocumentEditor.markDirty()

  proc decorationComponentRequiredSignColumnWidth(self: DecorationComponent, visibleLines: Range[int]): int =
    let self = self.DecorationComponentImpl
    case self.settings.show.get()
    of SignColumnShowKind.Auto:
      var width = 0
      for line in visibleLines.a..visibleLines.b:
        self.signs.withValue(line, value):
          var subWidth = 0
          for s in value[]:
            subWidth += s.width
          width = max(width, subWidth)

      let maxWidth = self.settings.maxWidth.get()
      if maxWidth >= 0:
        width = min(width, maxWidth)
      return width

    of SignColumnShowKind.Yes:
      let maxWidth = self.settings.maxWidth.get()
      if maxWidth < 0:
        return 1
      return maxWidth

    of SignColumnShowKind.No:
      return 0

    of SignColumnShowKind.Number:
      return 0

  iterator splitSelectionIntoLines(selection: Selection, includeAfter: bool = true): Selection =
    ## Yields a selection for each line covered by the input selection, covering the same range as the input
    ## If includeAfter is true then the selections will go until line.len, otherwise line.high

    let selection = selection.normalized
    if selection.first.line == selection.last.line:
      yield selection
    else:
      yield (
        selection.first,
        (selection.first.line, uint32.high.int)
      )

      for i in (selection.first.line + 1)..<selection.last.line:
        yield ((i, 0), (i, uint32.high.int))

      yield ((selection.last.line, 0), selection.last)

  proc decorationComponentClearCustomHighlights(self: DecorationComponent, id: Id) =
    ## Removes all custom highlights associated with the given id
    let self = self.DecorationComponentImpl

    var anyChanges = false
    for highlights in self.customHighlights.mvalues:
      for i in countdown(highlights.high, 0):
        if highlights[i].id == id:
          highlights.removeSwap(i)
          anyChanges = true

    if anyChanges:
      self.owner.DocumentEditor.markDirty()

  proc addCustomHighlight*(self: DecorationComponent, id: Id, selection: Selection, color: string, tint: Color = color(1, 1, 1)) {.inline.} =
    let self = self.DecorationComponentImpl
    for lineSelection in splitSelectionIntoLines(selection):
      assert lineSelection.first.line == lineSelection.last.line
      self.customHighlights.withValue(lineSelection.first.line, val):
        val[].add (id, lineSelection, color, tint)
      do:
        self.customHighlights[lineSelection.first.line] = @[(id, lineSelection, color, tint)]
    self.owner.DocumentEditor.markDirty()

  proc decorationComponentAddCustomHighlight(self: DecorationComponent, id: Id, selection: Range[Point], color: string, tint: Color = color(1, 1, 1)) =
    self.addCustomHighlight(id, selection.toSelection, color, tint)

  proc decorationComponentClearOverlays(self: DecorationComponent, id: int = -1) =
    let self = self.DecorationComponentImpl
    self.displayMap.overlay.clear(id)
    self.owner.DocumentEditor.markDirty()

  proc toInternal(location: OverlayRenderLocation): overlay_map.OverlayRenderLocation =
    case location
      of OverlayRenderLocation.Inline: overlay_map.OverlayRenderLocation.Inline
      of OverlayRenderLocation.Below: overlay_map.OverlayRenderLocation.Below
      of OverlayRenderLocation.Above: overlay_map.OverlayRenderLocation.Above

  proc decorationComponentAddOverlay(self: DecorationComponent, selection: Range[Point], text: string, id: int, scope: string, bias: Bias, renderId: int = 0, location: OverlayRenderLocation = OverlayRenderLocation.Inline) =
    let self = self.DecorationComponentImpl
    let location = location.toInternal
    self.displayMap.overlay.addOverlay(selection, text, id, scope, bias, renderId, location)
    self.owner.DocumentEditor.markDirty()

  proc decorationComponentAddOverlays(self: DecorationComponent, id: int, replace: bool, overlays: sink seq[OverlayDef]) =
      let self = self.DecorationComponentImpl
      self.displayMap.overlay.addOverlays(id, replace, overlays.mapIt((it.range, it.text, it.scope, it.bias, it.renderId, it.location.toInternal)))
      self.owner.DocumentEditor.markDirty()

  proc decorationComponentAddCustomRenderer(self: DecorationComponent, impl: CustomOverlayRenderer): CustomRendererId =
    let self = self.DecorationComponentImpl
    return self.customOverlayRenderers.add(impl)

  proc decorationComponentRemoveCustomRenderer(self: DecorationComponent, id: CustomRendererId) =
    let self = self.DecorationComponentImpl
    self.customOverlayRenderers.del(id)

  proc decorationComponentAllocateOverlayId(self: DecorationComponent): Option[int] =
    let self = self.DecorationComponentImpl
    return self.displayMap.overlay.allocateId()

  proc decorationComponentReleaseOverlayId(self: DecorationComponent, id: int) =
    let self = self.DecorationComponentImpl
    self.displayMap.overlay.releaseId(id)
