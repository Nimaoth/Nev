import vmath, bumpy, chroma
import misc/[util, custom_logger, fuzzy_matching]
import ui/node
import platform/platform
import ui/[widget_builders_base, widget_library]
import text/text_editor
import app, selector_popup, theme, file_selector_item

logCategory "selector-popup-ui"

# Mark this entire file as used, otherwise we get warnings when importing it but only calling a method
{.used.}

method createUI*(self: FileSelectorItem, popup: SelectorPopup, builder: UINodeBuilder, app: App): seq[proc() {.closure.}] =
  let textColor = app.theme.color("editor.foreground", color(0.9, 0.8, 0.8))
  let name = if self.name.len > 0: self.name else: self.path
  let matchIndices = self.getCompletionMatches(popup.getSearchString(), name, defaultPathMatchingConfig)
  builder.panel(&{LayoutHorizontal, FillX, SizeToContentY}):
    discard builder.highlightedText(name, matchIndices, textColor, textColor.lighten(0.15))

    if self.directory.len > 0:
      builder.panel(&{FillY}, w = builder.charWidth * 4)
      builder.panel(&{DrawText, SizeToContentX, SizeToContentY, TextItalic}, text = self.directory, textColor = textColor.darken(0.2))


method createUI*(self: SearchFileSelectorItem, popup: SelectorPopup, builder: UINodeBuilder, app: App): seq[proc() {.closure.}] =
  let textColor = app.theme.color("editor.foreground", color(0.9, 0.8, 0.8))
  let name = self.searchResult
  let matchIndices = self.getCompletionMatches(popup.getSearchString(), name, defaultPathMatchingConfig)
  builder.panel(&{LayoutHorizontalReverse, FillX, SizeToContentY}):
    builder.panel(&{DrawText, SizeToContentX, SizeToContentY}, text = fmt"| {self.path}:{self.line}", pivot = vec2(1, 0), textColor = textColor)
    builder.panel(&{FillX, SizeToContentY, MaskContent}, pivot = vec2(1, 0)):
      discard builder.highlightedText(name, matchIndices, textColor, textColor.lighten(0.15))

method createUI*(self: TextSymbolSelectorItem, popup: SelectorPopup, builder: UINodeBuilder, app: App): seq[proc() {.closure.}] =
  let textColor = app.theme.color("editor.foreground", color(0.9, 0.8, 0.8))
  let scopeColor = app.theme.tokenColor("string", color(175/255, 255/255, 175/255))

  builder.panel(&{FillX, SizeToContentY}):
    let matchIndices = self.getCompletionMatches(popup.getSearchString(), self.symbol.name, defaultCompletionMatchingConfig)
    discard builder.highlightedText(self.symbol.name, matchIndices, textColor, textColor.lighten(0.15))
    builder.panel(&{SizeToContentX, SizeToContentY, DrawText}, x = currentNode.w, text = $self.symbol.symbolType, pivot = vec2(1, 0), textColor = scopeColor)

method createUI*(self: NamedSelectorItem, popup: SelectorPopup, builder: UINodeBuilder, app: App): seq[proc() {.closure.}] =
  let textColor = app.theme.color("editor.foreground", color(0.9, 0.8, 0.8))
  let matchIndices = self.getCompletionMatches(popup.getSearchString(), self.name, defaultPathMatchingConfig)
  discard builder.highlightedText(self.name, matchIndices, textColor, textColor.lighten(0.15))

method createUI*(self: SelectorPopup, builder: UINodeBuilder, app: App): seq[proc() {.closure.}] =
  # let dirty = self.dirty
  self.resetDirty()

  var flags = &{UINodeFlag.MaskContent, OverlappingChildren}
  var flagsInner = &{LayoutVertical}

  let sizeToContentX = false
  let sizeToContentY = true
  if sizeToContentX:
    flags.incl SizeToContentX
    flagsInner.incl SizeToContentX
  else:
    flags.incl FillX
    flagsInner.incl FillX

  if sizeToContentY:
    flags.incl SizeToContentY
    flagsInner.incl SizeToContentY
  else:
    flags.incl FillY
    flagsInner.incl FillY

  let scale = (vec2(1, 1) - self.scale) * 0.5

  let bounds = builder.currentParent.boundsActual.shrink(absolute(scale.x * builder.currentParent.boundsActual.w), absolute(scale.y * builder.currentParent.boundsActual.h))
  builder.panel(&{SizeToContentY}, x = bounds.x, y = bounds.y, w = bounds.w, userId = self.userId.newPrimaryId):
    builder.panel(flags): #, userId = id):
      let totalLineHeight = app.platform.totalLineHeight
      let maxLineCount = if sizeToContentY:
        30
      else:
        floor(currentNode.boundsActual.h / totalLineHeight).int

      let targetNumRenderedItems = min(maxLineCount, self.completions.len)
      var lastRenderedIndex = min(self.scrollOffset + targetNumRenderedItems - 1, self.completions.high)

      if self.selected < self.scrollOffset:
        self.scrollOffset = self.selected
        lastRenderedIndex = min(self.scrollOffset + targetNumRenderedItems - 1, self.completions.high)

      if self.selected > lastRenderedIndex:
        self.scrollOffset = max(self.selected - targetNumRenderedItems + 1, 0)
        lastRenderedIndex = min(self.scrollOffset + targetNumRenderedItems - 1, self.completions.high)

      let backgroundColor = app.theme.color("panel.background", color(0.1, 0.1, 0.1)).withAlpha(1)
      let selectionColor = app.theme.color("list.activeSelectionBackground", color(0.8, 0.8, 0.8)).withAlpha(1)

      block:
        builder.panel(flagsInner):
          builder.panel(&{FillX, SizeToContentY}):
            result.add self.textEditor.createUI(builder, app)

          var widgetIndex = 0
          for completionIndex in self.scrollOffset..lastRenderedIndex:
            defer: inc widgetIndex

            let backgroundColor = if completionIndex == self.selected:
              selectionColor
            else:
              backgroundColor

            builder.panel(&{FillX, SizeToContentY, FillBackground}, backgroundColor = backgroundColor):
              result.add self.completions[self.completions.high - completionIndex].createUI(self, builder, app)

          # builder.panel(&{FillX, FillY, FillBackground}, backgroundColor = backgroundColor)
