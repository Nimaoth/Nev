import std/[strutils, sugar, sequtils]
import vmath, bumpy, chroma
import misc/[util, custom_logger, fuzzy_matching, disposable_ref]
import ui/node
import platform/platform
import ui/[widget_builders_base, widget_library]
import text/text_editor
import app, selector_popup, theme
import finder/[finder, previewer, file_previewer, open_editor_previewer, data_previewer]
import config_provider, events

# Mark this entire file as used, otherwise we get warnings when importing it but only calling a method
{.used.}

{.push gcsafe.}
{.push raises: [].}

logCategory "selector-popup-ui"

proc createUI*(self: SelectorPopup, i: int, item: FinderItem, builder: UINodeBuilder, app: App):
    seq[OverlayFunction] =

  let textColor = app.themes.theme.color("editor.foreground", color(0.9, 0.8, 0.8))
  let highlightColor = app.themes.theme.color("editor.foreground.highlight", textColor.lighten(0.18))
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

method createUI*(self: SelectorPopup, builder: UINodeBuilder): seq[OverlayFunction] =
  let app = ({.gcsafe.}: gEditor)
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

  let textColor = app.themes.theme.color("editor.foreground", color(0.9, 0.8, 0.8))
  let backgroundColor = app.themes.theme.color("panel.background", color(0.1, 0.1, 0.1)).withAlpha(1)
  let selectionColor = app.themes.theme.color("list.activeSelectionBackground",
    color(0.8, 0.8, 0.8)).withAlpha(1)
  let titleBackgroundColor = app.themes.theme.color(@["selector.title.background", "panel.background"], color(0.1, 0.1, 0.1)).withAlpha(1)
  let titleForegroundColor = app.themes.theme.color(@["selector.title.foreground", "editor.foreground"], color(0.1, 0.1, 0.1)).withAlpha(1)

  let excluded = ["prev", "next", "accept", "close"]
  proc filterCommand(s: string): bool =
    return not excluded.anyIt(s.toLowerAscii.startsWith(it))
  let nextPossibleInputs = app.getNextPossibleInputs(false, (handler) => handler.config.context.startsWith("popup.selector")).filterIt(filterCommand(it.description))
  var whichKeyHeight = app.config.runtime.get("ui.selector-popup.which-key-height", 5)
  whichKeyHeight = (nextPossibleInputs.len + 1) div 2

  builder.panel(&{FillBackground}, x = bounds.x, y = bounds.y, w = bounds.w, h = bounds.h,
      backgroundColor = backgroundColor, userId = self.userId.newPrimaryId):

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

            builder.panel(&{FillX, FillY, LayoutHorizontalReverse}):
              if self.finder.isNotNil and self.finder.filteredItems.getSome(items):
                let text = &"{items.filteredLen}/{items.len}"
                builder.panel(&{SizeToContentX, SizeToContentY, DrawText}, text = text, textColor = textColor, pivot = vec2(1, 0))
              if self.finder.isNotNil and self.finder.filteredItems.getSome(items) and items.locked:
                builder.panel(&{SizeToContentX, SizeToContentY, DrawText}, text = "...", textColor = textColor, pivot = vec2(1, 0))

          if self.finder.isNotNil and self.finder.filteredItems.getSome(items) and items.filteredLen > 0:
            let highlightColor = app.themes.theme.color("editor.foreground.highlight", textColor.lighten(0.18))
            let detailColor = textColor.darken(0.2)

            var rows: seq[seq[UINode]] = @[]
            builder.panel(&{FillX, LayoutVertical} + yFlag):
              if not items.locked:
                let nextKeyHeight = whichKeyHeight.float * builder.textHeight
                let maxLineCount = max(floor((bounds.h - nextKeyHeight) / totalLineHeight).int - 1, 1)
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

                self.cachedFinderItems.setLen(0)
                for completionIndex in self.scrollOffset..lastRenderedIndex:
                  self.cachedFinderItems.add items[completionIndex]
                self.cachedScrollOffset = self.scrollOffset

              for i, item in self.cachedFinderItems:
                let completionIndex = self.cachedScrollOffset + i
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
                      row.add builder.createTextWithMaxWidth($(item.score * 100), maxColumnWidth, "...", detailColor, &{TextItalic})

                    row.add builder.highlightedText(name, matchIndices, textColor, highlightColor, maxDisplayNameWidth)

                    if item.details.len > 0:
                      for detail in item.details:
                        row.add builder.createTextWithMaxWidth(detail, maxColumnWidth, "...", detailColor, &{TextItalic})

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

          if app.nextPossibleInputs.len == 0:
            let textColor = app.themes.theme.color("editor.foreground", color(0.882, 0.784, 0.784))
            let continuesTextColor = app.themes.theme.tokenColor("keyword", color(0.882, 0.784, 0.784))
            let keysTextColor = app.themes.theme.tokenColor("number", color(0.882, 0.784, 0.784))
            var headerColor = app.themes.theme.color("tab.inactiveBackground", color(0.176, 0.176, 0.176))
            builder.renderCommandKeys(nextPossibleInputs, textColor, continuesTextColor, keysTextColor, headerColor, whichKeyHeight, currentNode.bounds, padding = 0)

        if showPreview:
          builder.panel(0.UINodeFlags, x = bounds.w * (1 - previewScale),
              w = bounds.w * previewScale, h = bounds.h):

            self.previewEditor.active = self.focusPreview

            if self.previewView != nil:
              result.add self.previewView.createUI(builder)
            elif self.previewer.isSome:
              result.add self.previewer.get.get.createUI(builder)

    if sizeToContentY:
      currentNode.h = currentNode.last.h
