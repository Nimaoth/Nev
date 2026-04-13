#use
import std/[options]
import misc/[event, custom_async, jsonex]
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
  import std/[strformat]
  import misc/[util, custom_logger, rope_utils]
  import nimsumtree/[rope]
  import document, document_editor, text_component, text_editor_component
  import service

  logCategory "snippet-component"

  var SnippetComponentId: ComponentTypeId = componentGenerateTypeId()

  proc getSnippetComponent*(self: ComponentOwner): Option[SnippetComponent] =
    return self.getComponent(SnippetComponentId).mapIt(it.SnippetComponent)

  proc newSnippetComponent*(): SnippetComponent =
    return SnippetComponent(
      typeId: SnippetComponentId,
      initializeImpl: (proc(self: Component, owner: ComponentOwner) =
        let self = self.SnippetComponent
      ),
      deinitializeImpl: (proc(self: Component) =
        let self = self.SnippetComponent
      ),
    )

  proc init_module_snippet_component*() {.cdecl, exportc, dynlib.} =
    discard

{.pop.}
