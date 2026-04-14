#use
import std/[options]
import misc/[custom_async]
import component, text/snippet

export component

const currentSourcePath2 = currentSourcePath()
include module_base

type
  SnippetComponent* = ref object of Component
    currentSnippetData*: Option[SnippetData]

{.push gcsafe, raises: [].}

# DLL API
{.push rtl.}
proc getSnippetComponent*(self: ComponentOwner): Option[SnippetComponent]
proc newSnippetComponent*(): SnippetComponent

# proc snippetComponentClearOverlayViews(self: SnippetComponent)
{.pop.}

# Nice wrappers
{.push inline.}
# proc clearSnippetView*(self: SnippetComponent) = snippetComponentClearSnippetView(self)

proc hasTabStops*(self: SnippetComponent): bool =
  return self.currentSnippetData.isSome

proc clearTabStops*(self: SnippetComponent) =
  self.currentSnippetData = SnippetData.none
{.pop.}

# Implementation
when implModule:
  import misc/[util, custom_logger]
  import document, document_editor, text_component, text_editor_component

  logCategory "snippet-component"

  var SnippetComponentId: ComponentTypeId = componentGenerateTypeId()

  proc getSnippetComponent*(self: ComponentOwner): Option[SnippetComponent] =
    return self.getComponent(SnippetComponentId).mapIt(it.SnippetComponent)

  proc newSnippetComponent*(): SnippetComponent =
    return SnippetComponent(
      typeId: SnippetComponentId,
    )

  proc init_module_snippet_component*() {.cdecl, exportc, dynlib.} =
    discard

{.pop.}
