import std/[strutils]
import vmath, bumpy, chroma
import misc/[util, custom_logger, fuzzy_matching]
import ui/node
import platform/platform
import ui/[widget_builders_base, widget_library]
import text/text_editor
import app, selector_popup, theme
import finder/finder
import config_provider

# Mark this entire file as used, otherwise we get warnings when importing it but only calling a method
{.used.}

{.push gcsafe.}
{.push raises: [].}

logCategory "selector-popup-ui"

proc createUI*(self: SelectorPopup, i: int, item: FinderItem, builder: UINodeBuilder, app: App):
    seq[OverlayFunction] =

  let textColor = app.theme.color("editor.foreground", color(0.9, 0.8, 0.8))
  let name = item.displayName
  let matchIndices = self.getCompletionMatches(i, self.getSearchString(), name, defaultPathMatchingConfig)

  builder.panel(&{LayoutHorizontal, FillX, SizeToContentY}):
    discard builder.highlightedText(name, matchIndices, textColor, textColor.lighten(0.15))

    if item.detail.len > 0:
      builder.panel(&{FillY}, w = builder.charWidth * 4)
      builder.panel(&{DrawText, SizeToContentX, SizeToContentY, TextItalic}, text = item.detail,
        textColor = textColor.darken(0.2))

method createUI*(self: SelectorPopup, builder: UINodeBuilder, app: App): seq[OverlayFunction] =
  # let dirty = self.dirty
  self.resetDirty()

  let showPreview = self.previewEditor.isNotNil and self.previewVisible
  let previewScale = if showPreview: self.previewScale else: 0

  let sizeToContentY = not showPreview and self.sizeToContentY
  var yFlag = if sizeToContentY:
    &{SizeToContentY}
  else:
    &{FillY}

  let scale = (vec2(1, 1) - self.scale) * 0.5

  let bounds = builder.currentParent.boundsActual.shrink(
    absolute(scale.x * builder.currentParent.boundsActual.w),
    absolute(scale.y * builder.currentParent.boundsActual.h))

  let backgroundColor = app.theme.color("panel.background", color(0.1, 0.1, 0.1)).withAlpha(1)
  let selectionColor = app.theme.color("list.activeSelectionBackground",
    color(0.8, 0.8, 0.8)).withAlpha(1)

  builder.panel(&{FillBackground}, x = bounds.x, y = bounds.y, w = bounds.w, h = bounds.h,
      backgroundColor = backgroundColor, userId = self.userId.newPrimaryId):

    builder.panel(&{FillX, MaskContent, OverlappingChildren} + yFlag): #, userId = id):
      let totalLineHeight = app.platform.totalLineHeight

      block:
        builder.panel(&{FillX, LayoutVertical} + yFlag, w = bounds.w * (1 - previewScale)):

          builder.panel(&{FillX, SizeToContentY}):
            result.add self.textEditor.createUI(builder, app)

          if self.finder.isNotNil and self.finder.filteredItems.getSome(items) and items.filteredLen > 0:

            let textColor = app.theme.color("editor.foreground", color(0.9, 0.8, 0.8))
            let highlightColor = textColor.lighten(0.15)
            let detailColor = textColor.darken(0.2)

            var rows: seq[seq[UINode]] = @[]

            builder.panel(&{FillX, LayoutVertical} + yFlag):
              let maxLineCount = floor(bounds.h / totalLineHeight).int
              let targetNumRenderedItems = min(maxLineCount, items.filteredLen)
              var lastRenderedIndex = min(self.scrollOffset + targetNumRenderedItems - 1, items.filteredLen - 1)

              if self.selected < self.scrollOffset:
                self.scrollOffset = self.selected
                lastRenderedIndex = min(self.scrollOffset + targetNumRenderedItems - 1, items.filteredLen - 1)

              if self.selected > lastRenderedIndex:
                self.scrollOffset = max(self.selected - targetNumRenderedItems + 1, 0)
                lastRenderedIndex = min(self.scrollOffset + targetNumRenderedItems - 1, items.filteredLen - 1)

              assert self.scrollOffset >= 0
              assert self.scrollOffset < items.filteredLen

              assert lastRenderedIndex >= 0
              assert lastRenderedIndex < items.filteredLen

              var widgetIndex = 0
              for completionIndex in self.scrollOffset..lastRenderedIndex:
                defer: inc widgetIndex

                let fillBackgroundFlag = if completionIndex == self.selected:
                  &{FillBackground}
                else:
                  0.UINodeFlags

                let maxDisplayNameWidth = self.maxDisplayNameWidth
                let maxColumnWidth = self.maxColumnWidth

                builder.panel(&{FillX, SizeToContentY} + fillBackgroundFlag,
                    backgroundColor = selectionColor):

                  let item {.cursor.} = items[completionIndex]

                  let name = item.displayName
                  let matchIndices = self.getCompletionMatches(
                    completionIndex, self.getSearchString(), name, defaultPathMatchingConfig)

                  var row: seq[UINode] = @[]

                  builder.panel(&{FillX, SizeToContentY}):
                    if app.config.getOption("ui.selector.show-score", false):
                      row.add builder.createTextWithMaxWidth($item.score, maxColumnWidth, "...", detailColor, &{TextItalic})

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

        if showPreview:
          builder.panel(0.UINodeFlags, x = bounds.w * (1 - previewScale),
              w = bounds.w * previewScale, h = bounds.h):

            self.previewEditor.active = self.focusPreview
            result.add self.previewEditor.createUI(builder, app)

    if sizeToContentY:
      currentNode.h = currentNode.last.h
