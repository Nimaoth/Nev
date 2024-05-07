import std/[strutils]
import vmath, bumpy, chroma
import misc/[util, custom_logger, fuzzy_matching]
import ui/node
import platform/platform
import ui/[widget_builders_base, widget_library]
import text/text_editor
import app, selector_popup, theme, file_selector_item
import finder/finder

logCategory "selector-popup-ui"

# Mark this entire file as used, otherwise we get warnings when importing it but only calling a method
{.used.}

proc createUI*(self: SelectorPopup, i: int, item: FinderItem, builder: UINodeBuilder, app: App):
    seq[proc() {.closure.}] =

  let textColor = app.theme.color("editor.foreground", color(0.9, 0.8, 0.8))
  let name = item.displayName
  let matchIndices = self.getCompletionMatches(i, self.getSearchString(), name, defaultPathMatchingConfig)

  builder.panel(&{LayoutHorizontal, FillX, SizeToContentY}):
    discard builder.highlightedText(name, matchIndices, textColor, textColor.lighten(0.15))

    if item.detail.len > 0:
      builder.panel(&{FillY}, w = builder.charWidth * 4)
      builder.panel(&{DrawText, SizeToContentX, SizeToContentY, TextItalic}, text = item.detail,
        textColor = textColor.darken(0.2))

method createUI*(self: SelectorPopup, builder: UINodeBuilder, app: App): seq[proc() {.closure.}] =
  # let dirty = self.dirty
  self.resetDirty()

  var flags = &{UINodeFlag.MaskContent, OverlappingChildren}
  var flagsInner = &{LayoutVertical}

  let sizeToContentY = self.previewEditor.isNil
  var yFlag = if sizeToContentY:
    &{SizeToContentY}
  else:
    &{FillY}

  flags.incl FillX
  flagsInner.incl FillX

  flags = flags + yFlag
  flagsInner = flagsInner + yFlag

  let scale = (vec2(1, 1) - self.scale) * 0.5

  let bounds = builder.currentParent.boundsActual.shrink(
    absolute(scale.x * builder.currentParent.boundsActual.w),
    absolute(scale.y * builder.currentParent.boundsActual.h))

  builder.panel(&{}, x = bounds.x, y = bounds.y, w = bounds.w, h = bounds.h,
      userId = self.userId.newPrimaryId):

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
      let selectionColor = app.theme.color("list.activeSelectionBackground",
        color(0.8, 0.8, 0.8)).withAlpha(1)

      const previewSize = 0.5

      block:
        builder.panel(flagsInner, w = bounds.w * (1 - previewSize)):
          builder.panel(&{FillX, SizeToContentY}):
            result.add self.textEditor.createUI(builder, app)

          if self.finder.isNotNil and self.finder.filteredItems.getSome(items):

            let textColor = app.theme.color("editor.foreground", color(0.9, 0.8, 0.8))
            let highlightColor = textColor.lighten(0.15)
            let detailColor = textColor.darken(0.2)

            var rows: seq[seq[UINode]] = @[]

            builder.panel(&{FillX, FillBackground, LayoutVertical} + yFlag, backgroundColor = backgroundColor):
              var widgetIndex = 0
              for completionIndex in self.scrollOffset..lastRenderedIndex:
                defer: inc widgetIndex

                let backgroundColor = if completionIndex == self.selected:
                  selectionColor
                else:
                  backgroundColor

                const maxDisplayNameWidth = 50
                const maxColumnWidth = 60

                builder.panel(&{FillX, SizeToContentY, FillBackground}, backgroundColor = backgroundColor):
                  let rawCompletionIndex = self.completions.high - completionIndex
                  let completion {.cursor.} = self.completions[rawCompletionIndex]
                  assert completion.finderItemIndex < items.len
                  if completion.finderItemIndex < items.len:
                    let item {.cursor.} = items[completion.finderItemIndex]

                    let name = item.displayName
                    let matchIndices = self.getCompletionMatches(
                      completionIndex, self.getSearchString(), name, defaultPathMatchingConfig)

                    var row: seq[UINode] = @[]

                    builder.panel(&{FillX, SizeToContentY}):
                      row.add builder.highlightedText(name, matchIndices, textColor,
                        highlightColor, maxDisplayNameWidth)

                      if item.detail.len > 0:
                        let details = item.detail.split('\t')
                        for detail in details:
                          row.add builder.createTextWithMaxWidth(detail, maxColumnWidth, "...",
                            detailColor, &{TextItalic})

                    rows.add row

            # Align grid
            var maxWidths: seq[float] = @[]
            for row, nodes in rows:
              for col, node in nodes:
                while maxWidths.len <= col:
                  maxWidths.add 0
                maxWidths[col] = max(maxWidths[col], node.bounds.w)

            let gap = 4 * builder.charWidth

            for row, nodes in rows:
              var x = 0.0
              for col, node in nodes:
                node.rawX = x
                x += maxWidths[col] + gap

        if self.previewEditor.isNotNil:
          builder.panel(0.UINodeFlags, x = bounds.w * (1 - previewSize), w = bounds.w * previewSize, h = bounds.h):
            result.add self.previewEditor.createUI(builder, app)
