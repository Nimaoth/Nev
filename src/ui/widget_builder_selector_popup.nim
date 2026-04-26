import std/[strutils, sugar, sequtils]
import vmath, bumpy, chroma
import misc/[util, custom_logger, disposable_ref]
import ui/node
import platform/platform
import ui/[widget_library]
import text/text_editor
import app, selector_popup, theme
import finder/[finder, previewer, file_previewer, open_editor_previewer, data_previewer]
import config_provider, events, view

# Mark this entire file as used, otherwise we get warnings when importing it but only calling a method
{.used.}

{.push gcsafe.}
{.push raises: [].}

logCategory "selector-popup-ui"

proc createUI*(self: SelectorPopup, i: int, item: FinderItem, builder: UINodeBuilder, app: App):
    seq[OverlayFunction] =

  let textColor = app.themes.theme.color("editor.foreground", color(0.9, 0.8, 0.8))
  let name = item.displayName
  let matchIndices = self.getCompletionMatches(i, self.getSearchString(), name, finderFuzzyMatchConfig)

  builder.panel(&{LayoutHorizontal, FillX, SizeToContentY}):
    discard builder.highlightedText(name, matchIndices, textColor, textColor.lighten(0.15))

    if item.details.len > 0:
      builder.panel(&{FillY}, w = builder.charWidth * 4)
      builder.panel(&{DrawText, SizeToContentX, SizeToContentY, TextItalic}, text = $item.details,
        textColor = textColor.darken(0.2))

method createUI*(self: FilePreviewer, builder: UINodeBuilder): seq[OverlayFunction] =
  if self.editor.isNotNil:
    result.add self.editor.createUI(builder)

method createUI*(self: OpenEditorPreviewer, builder: UINodeBuilder): seq[OverlayFunction] =
  if self.editor.isNotNil:
    result.add self.editor.createUI(builder)

method createUI*(self: DataPreviewer, builder: UINodeBuilder): seq[OverlayFunction] =
  if self.editor.isNotNil:
    result.add self.editor.createUI(builder)

proc selectorPopupCreateUI*(self: SelectorPopup, builder: UINodeBuilder): seq[OverlayFunction] =
  let app = ({.gcsafe.}: gEditor)
  # let dirty = self.dirty
  self.resetDirty()

  defer:
    self.scrollToSelected = false

  let showPreview = self.previewEditor.isNotNil and self.previewVisible
  let previewScale = if showPreview: self.previewScale else: 0

  let sizeToContentY = not showPreview and self.sizeToContentY
  var yFlag = if sizeToContentY:
    &{SizeToContentY}
  else:
    &{FillY}

  let scale = (vec2(1, 1) - self.scale) * 0.5

  var bounds = builder.currentParent.boundsActual.shrink(
    absolute(scale.x * builder.currentParent.boundsActual.w),
    absolute(scale.y * builder.currentParent.boundsActual.h))
  bounds.x = ((bounds.x / builder.charWidth).floor() * builder.charWidth).round() - 1
  bounds.y = ((bounds.y / builder.textHeight).floor() * builder.textHeight).round() - 1
  bounds.w = ((bounds.w / builder.charWidth).ceil() * builder.charWidth).round() + 2
  bounds.h = ((bounds.h / builder.textHeight).ceil() * builder.textHeight).round() + 2

  let textColor = app.themes.theme.color("editor.foreground", color(0.9, 0.8, 0.8))
  let backgroundColor = app.themes.theme.color("panel.background", color(0.1, 0.1, 0.1)).withAlpha(1)
  let borderColor = app.themes.theme.color("panel.border", backgroundColor.lighten(0.2))
  let selectionColor = app.themes.theme.color("list.activeSelectionBackground",
    color(0.8, 0.8, 0.8)).withAlpha(1)
  let titleBackgroundColor = app.themes.theme.color(@["selector.title.background", "panel.background"], color(0.1, 0.1, 0.1)).withAlpha(1)
  let titleForegroundColor = app.themes.theme.color(@["selector.title.foreground", "editor.foreground"], color(0.1, 0.1, 0.1)).withAlpha(1)

  let excluded = ["prev", "next", "accept", "close"]
  proc filterCommand(s: string): bool =
    return not excluded.anyIt(s.toLowerAscii.startsWith(it))
  let nextPossibleInputs = app.getNextPossibleInputs(false, (handler) => handler.config.context.startsWith("popup.selector")).filterIt(filterCommand(it.description))
  let uiSettings = UiSettings.new(app.config.runtime)
  var whichKeyHeightLines = uiSettings.popupWhichKeyHeight.get()
  whichKeyHeightLines = (nextPossibleInputs.len + 1) div 2
  let whichKeyHeightPx = builder.renderCommandKeysHeight(whichKeyHeightLines, padding = 0)

  builder.panel(&{FillBackground, DrawBorder, DrawBorderTerminal}, x = bounds.x, y = bounds.y, w = bounds.w, h = bounds.h, border = border(1),
      backgroundColor = backgroundColor, borderColor = borderColor, userId = self.userId.newPrimaryId):

    builder.panel(&{FillX, MaskContent, OverlappingChildren} + yFlag): #, userId = id):
      let totalLineHeight = app.platform.totalLineHeight

      block:
        builder.panel(&{FillX, LayoutVertical} + yFlag, w = bounds.w * (1 - previewScale)):
          let leftBounds = currentNode.bounds

          let title = if self.title != "": self.title else: self.scope
          if title != "":
            builder.panel(&{SizeToContentX, SizeToContentY, DrawText, FillBackground},
              text = title,
              pivot = vec2(0.5, 0),
              textColor = titleForegroundColor,
              backgroundColor = titleBackgroundColor,
              x = leftBounds.w * 0.5)

          builder.panel(&{FillX, SizeToContentY}):
            result.add self.textEditor.createUI(builder)
            builder.updateSizeToContent(currentNode)

            builder.panel(&{FillX, FillY, LayoutHorizontalReverse}):
              if self.finder.isNotNil and self.finder.filteredItems.getSome(items):
                let text = &"{items.filteredLen}/{items.len}"
                builder.panel(&{SizeToContentX, SizeToContentY, DrawText}, text = text, textColor = textColor, pivot = vec2(1, 0))
              if self.finder.isNotNil and self.finder.filteredItems.getSome(items) and items.locked:
                builder.panel(&{SizeToContentX, SizeToContentY, DrawText}, text = "...", textColor = textColor, pivot = vec2(1, 0))
          builder.updateSizeToContent(currentNode)

          if self.finder.isNotNil and self.finder.filteredItems.getSome(items) and items.filteredLen > 0:
            let highlightColor = app.themes.theme.color("editor.foreground.highlight", textColor.lighten(0.18))
            let detailColor = textColor.darken(0.2)
            let detailsFontScale = app.config.runtime.get("ui.selector.details-font-scale", 0.85)

            var rows: seq[seq[UINode]] = @[]
            var rowsNode: UINode
            builder.panel(&{FillX, LayoutVertical} + yFlag):
              rowsNode = currentNode
              if not items.locked:
                let maxLineCount = if sizeToContentY:
                  30
                else:
                  max(floor((rowsNode.bounds.h - whichKeyHeightPx) / totalLineHeight).int, 1)
                let targetNumRenderedItems = min(maxLineCount, items.filteredLen)
                var lastRenderedIndex = min(self.scrollOffset + targetNumRenderedItems - 1, items.filteredLen - 1)

                if self.scrollToSelected:
                  if self.selected < self.scrollOffset:
                    self.scrollOffset = self.selected
                    lastRenderedIndex = min(self.scrollOffset + targetNumRenderedItems - 1, items.filteredLen - 1)

                  if self.selected > lastRenderedIndex:
                    self.scrollOffset = max(self.selected - targetNumRenderedItems + 1, 0)
                    lastRenderedIndex = min(self.scrollOffset + targetNumRenderedItems - 1, items.filteredLen - 1)

                let numRenderedItems = lastRenderedIndex - self.scrollOffset + 1
                self.scrollOffset = clamp(self.scrollOffset, 0, items.filteredLen - numRenderedItems)

                assert self.scrollOffset >= 0
                assert self.scrollOffset < items.filteredLen
                assert lastRenderedIndex >= 0
                assert lastRenderedIndex < items.filteredLen

                onScroll:
                  self.scrollOffset = clamp(self.scrollOffset - delta.y.int, 0, items.filteredLen - numRenderedItems)
                  self.markDirty()

                self.cachedFinderItems.setLen(0)
                for completionIndex in self.scrollOffset..lastRenderedIndex:
                  if items.isValidIndex(completionIndex):
                    self.cachedFinderItems.add items[completionIndex]
                self.cachedScrollOffset = self.scrollOffset

              for i, item in self.cachedFinderItems:
                let completionIndex = self.cachedScrollOffset + i
                if not items.isValidIndex(completionIndex):
                  continue

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
                  let matchIndices = self.getCompletionMatches(completionIndex, self.getSearchString(), name, finderFuzzyMatchConfig)

                  var row: seq[UINode] = @[]

                  builder.panel(&{FillX, SizeToContentY}):
                    if app.config.runtime.get("ui.selector.show-score", false):
                      row.add builder.createTextWithMaxWidth($(item.score * 100), maxColumnWidth, "...", detailColor, &{TextItalic}, fontScale = detailsFontScale)

                    row.add builder.highlightedText(name, matchIndices, textColor, highlightColor, maxDisplayNameWidth)

                    if item.details.len > 0:
                      for detail in item.details:
                        row.add builder.createTextWithMaxWidth(detail, maxColumnWidth, "...", detailColor, &{TextItalic}, fontScale = detailsFontScale)

                  rows.add row

            # Align grid
            var maxWidths: seq[float] = @[]
            var maxHeights: seq[float] = @[]
            for row, nodes in rows:
              while maxHeights.len <= row:
                maxHeights.add 0
              for col, node in nodes:
                while maxWidths.len <= col:
                  maxWidths.add 0
                maxWidths[col] = max(maxWidths[col], node.bounds.w)
                maxHeights[row] = max(maxHeights[row], node.bounds.h)

            let gap = 1 * builder.charWidth

            for row, nodes in rows:
              var x = 0.0
              for col, node in nodes:
                node.rawX = x
                x += maxWidths[col] + gap
                # Center all nodes vertically based on the row height
                node.rawY = floor((maxHeights[row] - node.bounds.h) * 0.5)

            # Scroll bar
            buildCommands(rowsNode.renderCommands):
              if items.filteredLen > rows.len:
                let scrollBarColor = builder.theme.color(@["scrollBar", "scrollbarSlider.background"],
                  backgroundColor.lighten(0.1))
                let thumbHeightRatio = rows.len.float / items.filteredLen.float
                let availableHeight = rowsNode.bounds.h - whichKeyHeightPx
                let thumbHeight = clamp(thumbHeightRatio * availableHeight.float, builder.textHeight,
                  max(availableHeight - builder.textHeight, availableHeight * 0.9))
                let scrollableHeight = availableHeight.float - thumbHeight
                let relativeScroll = self.scrollOffset.float / (items.filteredLen - rows.len).float
                let thumbY = relativeScroll * scrollableHeight
                let w = ceil(builder.charWidth * 0.5)
                fillRect(rect(rowsNode.bounds.w - w, floor(thumbY), w, ceil(thumbHeight)), scrollBarColor)

          builder.updateSizeToContent(currentNode)
          if SizeToContentY in yFlag:
            let textColor = app.themes.theme.color("editor.foreground", color(0.882, 0.784, 0.784))
            let continuesTextColor = app.themes.theme.tokenColor("keyword", color(0.882, 0.784, 0.784))
            let keysTextColor = app.themes.theme.tokenColor("number", color(0.882, 0.784, 0.784))
            var headerColor = app.themes.theme.color("tab.inactiveBackground", color(0.176, 0.176, 0.176))
            builder.renderCommandKeys(nextPossibleInputs, textColor, continuesTextColor, keysTextColor, headerColor, whichKeyHeightLines, currentNode.bounds, padding = 0)

        if SizeToContentY notin yFlag:
          let textColor = app.themes.theme.color("editor.foreground", color(0.882, 0.784, 0.784))
          let continuesTextColor = app.themes.theme.tokenColor("keyword", color(0.882, 0.784, 0.784))
          let keysTextColor = app.themes.theme.tokenColor("number", color(0.882, 0.784, 0.784))
          var headerColor = app.themes.theme.color("tab.inactiveBackground", color(0.176, 0.176, 0.176))
          builder.panel(&{FillX, FillY, LayoutVerticalReverse}):
            builder.panel(&{FillX, SizeToContentY}, pivot = vec2(0, 1)):
              builder.renderCommandKeys(nextPossibleInputs, textColor, continuesTextColor, keysTextColor, headerColor, whichKeyHeightLines, currentNode.bounds, padding = 0)
              builder.updateSizeToContent(currentNode)

        if showPreview:
          builder.panel(0.UINodeFlags, x = bounds.w * (1 - previewScale),
              w = bounds.w * previewScale, h = bounds.h, tag = "preview"):

            self.previewEditor.active = self.focusPreview

            if self.previewView != nil:
              result.add self.previewView.createUI(builder)
            elif self.previewer.isSome:
              result.add self.previewer.get.get.createUI(builder)

    if sizeToContentY:
      currentNode.h = currentNode.last.h + currentNode.border.top + currentNode.border.bottom

createUIImpl = selectorPopupCreateUI
