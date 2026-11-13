discard """
  action: "run"
  cmd: "nim $target --undef:useDynlib --nimblePath:./nimbleDir/simplePkgs $options $file"
  targets: "c"
"""

include ../../modules/text/widget_builder_text_document
{.pop.}
{.pop.}
{.pop.}
{.pop.}

import std/[importutils, unittest]
import nuigi/core/vecmath as nuiMath
import text_component, inlay_hint_component
import misc/[id, jsonex]

proc measureText(text: openArray[char], fontId: UiFontId,
    fontSize, maxWidth: float32, textFlags: UiTextFlags): UiTextArrangement {.raises: [].} =
  result.size = nuiMath.vec2(text.runeLen.int.float32 * 10, 20)

suite "Text editor sign column":
  test "two-cell signs replace line numbers in short documents":
    privateAccess(TextDocumentEditor)
    for content in ["abc", "abc\n".repeat(18)]:
      var b = newBuilder(measureText)
      let document = TextDocument(isInitialized: true, textComponent: newTextComponent())
      document.textComponent.buffer = initBuffer(content = content)
      let displayMap = DisplayMap.new()
      displayMap.setBuffer(document.buffer.snapshot.clone())
      let services = Services()
      services.addService(ThemeService.serviceName, ThemeService(theme: Theme()))
      let editor = TextDocumentEditor(document: document, displayMap: displayMap,
        services: services, renderHeader: false,
        platform: Platform(supportsThinCursor: true,
          charWidthImpl: proc(self: Platform): float {.gcsafe, raises: [].} = 10,
          lineHeightImpl: proc(self: Platform): float {.gcsafe, raises: [].} = 20),
        config: ConfigStore.new("sign-test", "", nil, newJexObject()),
        textEditorComponent: newTextEditorComponent(document))
      editor.textEditorComponent.displayMap = displayMap
      editor.addComponent(editor.textEditorComponent)
      editor.decorations = newDecorationComponent(displayMap)
      editor.addComponent(editor.decorations)
      editor.inlayHints = newInlayHintComponent(displayMap)
      editor.addComponent(editor.inlayHints)
      editor.config.setTextWrapLines(false)
      editor.config.setUiSyntaxHighlighting(false)
      editor.config.setUiLineNumbers(LineNumbers.Absolute)
      editor.config.setTextSignsShow(core_settings.SignColumnShowKind.Number)
      discard editor.decorations.addSign(idNone(), 0, "BP", width = 2)
      discard b.beginUiFrame(300, 200)
      b.node:
        discard b.size(200, 100)
        editor.createUINui(b)
      b.endUiFrame()
      var hasSign = false
      for i, node in b.frame.nodes:
        if node.textIndex > 0 and b.nodeText(i).text == "BP".uiString:
          hasSign = true
      check hasSign
      b.clearWidgetCaches()
