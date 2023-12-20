import vmath, bumpy, chroma
import misc/[util, custom_logger]
import ui/node
import app, selector_popup, platform, theme, widget_builders_base

# Mark this entire file as used, otherwise we get warnings when importing it but only calling a method
{.used.}

method createUI*(self: FileSelectorItem, builder: UINodeBuilder, app: App): seq[proc() {.closure.}] =
  let textColor = app.theme.color("editor.foreground", color(0.9, 0.8, 0.8))
  builder.panel(&{FillX, SizeToContentY, DrawText}, text = self.path, textColor = textColor)

method createUI*(self: TextSymbolSelectorItem, builder: UINodeBuilder, app: App): seq[proc() {.closure.}] =
  let textColor = app.theme.color("editor.foreground", color(0.9, 0.8, 0.8))
  let scopeColor = app.theme.tokenColor("string", color(175/255, 255/255, 175/255))

  builder.panel(&{FillX, SizeToContentY}):
    builder.panel(&{FillX, SizeToContentY, DrawText}, text = self.symbol.name, textColor = textColor)
    builder.panel(&{FillX, SizeToContentY, DrawText}, text = $self.symbol.symbolType, textColor = scopeColor)
    # typeText.right = -($self.symbol.symbolType).len.float * charWidth

method createUI*(self: ThemeSelectorItem, builder: UINodeBuilder, app: App): seq[proc() {.closure.}] =
  let textColor = app.theme.color("editor.foreground", color(0.9, 0.8, 0.8))
  builder.panel(&{FillX, SizeToContentY, DrawText}, text = self.path, textColor = textColor)

method createUI*(self: NamedSelectorItem, builder: UINodeBuilder, app: App): seq[proc() {.closure.}] =
  let textColor = app.theme.color("editor.foreground", color(0.9, 0.8, 0.8))
  builder.panel(&{FillX, SizeToContentY, DrawText}, text = self.name, textColor = textColor)

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

  let bounds = builder.currentParent.boundsActual.shrink(absolute(0.25 * builder.currentParent.boundsActual.w), absolute(0.25 * builder.currentParent.boundsActual.h))
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
              result.add self.completions[self.completions.high - completionIndex].createUI(builder, app)

          # builder.panel(&{FillX, FillY, FillBackground}, backgroundColor = backgroundColor)
