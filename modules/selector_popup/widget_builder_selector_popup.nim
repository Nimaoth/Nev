import std/[options, strutils, sugar, sequtils]
import vmath, bumpy, chroma
import misc/[util, custom_logger, disposable_ref]
import ui/node
import platform
import ui/[widget_library]
import selector_popup, theme, document_editor, core_settings
import finder, previewer, open_editor_previewer, data_previewer
import config_provider, input_handler/input_handler, view, file_previewer
import service
from nuigi import UiBuilder, UiNodeStorageData, UiBackendType, UiStyleIndex,
  UiTextStyleIndex,
  nodeStorageGet, nodeStorage, nodeStorageParent, currentNode, currentNodeIndex,
  fillX, fillY, fit, fitX, fitY, height, anchors, offsets, finishAnchors,
  layoutVertical, layoutHorizontal, node, text, textStyleIndex, styleIndex,
  fillBackground, padding, paddingY, gap, maskChildren, wasHovered, wasClicked,
  withParent, themeStyle, themeTextStyle
from nuigi/widgets import tableColumnFixed, tableColumnFill,
  tableColumnProportional, highlightedText
import nuigi/widgets/[dynamic_virtuallist, list_table]

# Mark this entire file as used, otherwise we get warnings when importing it but only calling a method
{.used.}

{.push gcsafe.}
{.push raises: [].}

logCategory "selector-popup-ui"

type SelectorPopupNuiStorage = ref object of UiNodeStorageData
  popup: SelectorPopupImpl
  listStorage: UiDynamicVirtualListStorage
  showScore: bool

proc getOrCreateSelectorPopupNuiStorage(
    b: var UiBuilder, node: auto): SelectorPopupNuiStorage =
  let existing = b.nodeStorageGet(node)
  if existing != nil:
    return cast[SelectorPopupNuiStorage](existing)
  var storage = SelectorPopupNuiStorage()
  b.nodeStorage(node, storage)
  storage

proc buildSelectorPopupRow(
    b: var UiBuilder, itemIndex: int, userData: int) {.nimcall, gcsafe, raises: [].} =
  if userData < 0 or userData >= b.frame.nodes.len:
    return
  let existing = b.nodeStorageGet(b.frame.nodes[userData].addr)
  if existing == nil or not (existing of SelectorPopupNuiStorage):
    return
  let storage = cast[SelectorPopupNuiStorage](existing)
  let popup = storage.popup
  if popup == nil or popup.finder == nil:
    return

  try:
    if popup.finder.filteredItems.isNone:
      return
    let filteredItems = popup.finder.filteredItems.get
    if not filteredItems.isValidIndex(itemIndex):
      return
    let item {.cursor.} = filteredItems[itemIndex]
    let selected = itemIndex == popup.selected
    let hovered = b.wasHovered(includeChildren = true)
    discard b.fitY()
      .styleIndex(if selected or hovered:
        UiStyleIndexMenuItemHover
      else:
        UiStyleIndexMenuItem)
      .fillBackground()

    b.node:
      discard b.fit().padding(2)
        .textStyleIndex(int(if selected:
          UiStyleIndexMenuItemHoverText
        else:
          UiStyleIndexMenuItemText))
        .text($(itemIndex + 1))

    if storage.showScore:
      b.node:
        discard b.fit().padding(2)
          .textStyleIndex(int(UiStyleIndexSmallText))
          .text($(item.score * 100.0))

    let labelStyle = if selected:
      UiStyleIndexMenuItemHoverText
    else:
      UiStyleIndexMenuItemText
    let labelColor = b.themeTextStyle(labelStyle)[].textColor
    let highlightColor = b.themeStyle(UiStyleIndexAccent)[].fillColor
    let matchIndices = popup.getCompletionMatches(itemIndex,
      popup.getSearchString(), item.displayName, finderFuzzyMatchConfig)
    b.node:
      discard b.fit().padding(2).maskChildren()
      b.highlightedText(item.displayName, matchIndices, labelColor,
        highlightColor, popup.maxDisplayNameWidth)

    b.node:
      discard b.fit().padding(2).maskChildren()
        .textStyleIndex(int(UiStyleIndexSmallText))
        .text(item.details.join("  "))

    if b.wasClicked(includeChildren = true):
      popup.selectNth(itemIndex)
      if popup.isInLayout:
        popup.accept()
  except:
    discard

proc selectorPopupCreateUINui*(self: SelectorPopupImpl, nui: var UiBuilder) =
  ## Builds the selector popup directly in Nuigi. The result list is virtualized
  ## and its direct row children are aligned by listTable.
  self.resetDirty()
  if self.textEditor == nil:
    return

  let showPreview = self.previewVisible and self.previewEditor != nil
  let previewScale = if showPreview:
    clamp(self.previewScale.float32, 0.1'f32, 0.9'f32)
  else:
    0.0'f32
  let rowHeight = if nui.backendType == UiBackendType.Terminal:
    1.0'f32
  else:
    26.0'f32
  let editorHeight = if nui.backendType == UiBackendType.Terminal:
    1.0'f32
  else:
    24
  let itemCount = self.getNumItems()
  let showScore = getServiceChecked(ConfigService).runtime.get(
    "ui.selector.show-score", false)

  template buildPopupContents() =
    block:
      nui.nodeStorageParent()
      let rootIndex = nui.currentNodeIndex
      let storage = nui.getOrCreateSelectorPopupNuiStorage(nui.currentNode)
      storage.popup = self
      storage.showScore = showScore

      nui.node("selector-popup-left"):
        if showPreview:
          discard nui.anchors(0.0'f32, 0.0'f32,
            1.0'f32 - previewScale, 1.0'f32).offsets(0, 0, -2, 0)
            .finishAnchors()
        else:
          discard nui.fillX().fillY()
        nui.layoutVertical("selector-popup-content"):
          discard nui.fillX().fillY().gap(2)
          let title = if self.title.len > 0: self.title else: self.scope
          if title.len > 0:
            nui.node("selector-popup-title"):
              discard nui.fillX().fitY().padding(4)
                .styleIndex(UiStyleIndexHeader).fillBackground()
                .textStyleIndex(int(UiStyleIndexHeaderText)).text(title)

          nui.node("selector-popup-search"):
            discard nui.fillX().height(editorHeight).maskChildren()
            self.textEditor.renderNui(nui)

          nui.node("selector-popup-results"):
            discard nui.fillX().fillY()
            var columns = @[
              tableColumnFixed(if nui.backendType == UiBackendType.Terminal:
                4.0'f32
              else:
                38.0'f32),
            ]
            if showScore:
              columns.add(tableColumnFixed(if nui.backendType == UiBackendType.Terminal:
                8.0'f32
              else:
                76.0'f32))
            columns.add(tableColumnProportional(2.0'f32))
            columns.add(tableColumnProportional(1.0'f32))
            storage.listStorage = nui.listTable(
              itemCount,
              rowHeight,
              columns,
              buildSelectorPopupRow,
              rootIndex,
              columnGap = if nui.backendType == UiBackendType.Terminal:
                1.0'f32
              else:
                6.0'f32)
            if self.scrollToSelected and storage.listStorage != nil and
                storage.listStorage.ensureItemVisible(
                  self.selected, storage.listStorage.viewportHeight, 0):
              self.scrollToSelected = false

          nui.layoutHorizontal("selector-popup-status"):
            discard nui.fillX().fitY().paddingY(2).gap(4)
            nui.node:
              var countText = "0/0"
              if self.finder != nil and self.finder.filteredItems.isSome:
                let filteredItems = self.finder.filteredItems.get
                countText = $filteredItems.filteredLen & "/" & $filteredItems.len
              discard nui.fit().textStyleIndex(int(UiStyleIndexSmallText))
                .text(countText)
            let isLocked = self.finder != nil and
              self.finder.filteredItems.isSome and
              self.finder.filteredItems.get.locked
            if isLocked:
              nui.node:
                discard nui.fit().textStyleIndex(int(UiStyleIndexSmallText))
                  .text("...")

      if showPreview:
        nui.node("selector-popup-preview"):
          discard nui.anchors(1.0'f32 - previewScale, 0.0'f32,
            1.0'f32, 1.0'f32).offsets(2, 0, 0, 0).finishAnchors()
            .styleIndex(UiStyleIndexPanel).fillBackground().padding(4)
            .maskChildren()
          if self.previewView != nil:
            self.previewView.render(nui)
          elif self.previewEditor != nil:
            self.previewEditor.renderNui(nui)

  if self.isInLayout:
    nui.node("selector-popup"):
      discard nui.fillX().fillY().styleIndex(UiStyleIndexMenu)
        .fillBackground().padding(4).maskChildren()
      buildPopupContents()
  else:
    nui.withParent(nui.overlays):
      nui.node("selector-popup"):
        let insetX = max(0.0'f32, (1.0'f32 - self.scale.x.float32) * 0.5'f32)
        let insetY = max(0.0'f32, (1.0'f32 - self.scale.y.float32) * 0.5'f32)
        if not showPreview and self.sizeToContentY:
          let titleHeight = if self.title.len > 0 or self.scope.len > 0:
            rowHeight
          else:
            0.0'f32
          let desiredHeight = titleHeight + editorHeight +
            min(itemCount, 30).float32 * rowHeight + rowHeight + 12.0'f32
          let maxHeight = max(rowHeight,
            nui.frame.nodes[0].size.y * self.scale.y.float32)
          let popupHeight = min(desiredHeight, maxHeight)
          discard nui.anchors(insetX, 0.5'f32, 1.0'f32 - insetX, 0.5'f32)
            .offsets(0, -popupHeight * 0.5'f32, 0, popupHeight * 0.5'f32)
            .finishAnchors()
        else:
          discard nui.anchors(insetX, insetY, 1.0'f32 - insetX,
            1.0'f32 - insetY).finishAnchors()
        discard nui.styleIndex(UiStyleIndexMenu).fillBackground().padding(4)
          .maskChildren()
        buildPopupContents()

proc createUI*(self: SelectorPopupImpl, i: int, item: FinderItem, builder: UINodeBuilder): seq[OverlayFunction] =
  let textColor = builder.theme.color("editor.foreground", color(0.9, 0.8, 0.8))
  let name = item.displayName
  let matchIndices = self.getCompletionMatches(i, self.getSearchString(), name, finderFuzzyMatchConfig)

  builder.panel(&{LayoutHorizontal, FillX, SizeToContentY}):
    discard builder.highlightedText(name, matchIndices, textColor, textColor.lighten(0.15))

    if item.details.len > 0:
      builder.panel(&{FillY}, w = builder.charWidth * 4)
      builder.panel(&{DrawText, SizeToContentX, SizeToContentY, TextItalic}, text = $item.details,
        textColor = textColor.darken(0.2))

proc selectorPopupCreateUI*(self: SelectorPopupImpl, builder: UINodeBuilder): seq[OverlayFunction] =
  # let dirty = self.dirty
  self.resetDirty()

  let config = getServiceChecked(ConfigService).runtime
  let events = getServiceChecked(EventHandlerService)

  defer:
    self.scrollToSelected = false

  let showPreview = self.previewEditor.isNotNil and self.previewVisible
  let previewScale = if showPreview: self.previewScale else: 0

  let sizeToContentY = not showPreview and self.sizeToContentY and not self.isInLayout
  var yFlag = if sizeToContentY:
    &{SizeToContentY}
  else:
    &{FillY}

  var bounds = rect(vec2(0), builder.currentParent.bounds.wh)
  if self.scale != vec2(1):
    let scale = (vec2(1, 1) - self.scale) * 0.5
    bounds = bounds.shrink(
      absolute(scale.x * builder.currentParent.bounds.w),
      absolute(scale.y * builder.currentParent.bounds.h))
    bounds.x = ((bounds.x / builder.charWidth).floor() * builder.charWidth).round() - 1
    bounds.y = ((bounds.y / builder.textHeight).floor() * builder.textHeight).round() - 1
    bounds.w = ((bounds.w / builder.charWidth).ceil() * builder.charWidth).round() + 2
    bounds.h = ((bounds.h / builder.textHeight).ceil() * builder.textHeight).round() + 2

  let selectorActive = (not self.isInLayout or self.active) and not self.focusPreview
  let inactiveBrightnessChange = config.getUiBackgroundInactiveBrightnessChange()
  let popupBrightnessChange = if not self.isInLayout: inactiveBrightnessChange * 0.5 else: 0.0
  var backgroundColor = if selectorActive:
    builder.theme.color("editor.background", color(25/255, 25/255, 40/255)).lighten(popupBrightnessChange)
  else:
    builder.theme.color("editor.background", color(25/255, 25/255, 25/255)).lighten(popupBrightnessChange + inactiveBrightnessChange)

  if config.getUiBackgroundTransparent():
    backgroundColor.a = 0
  else:
    backgroundColor.a = 1

  var headerColor = if selectorActive:
    builder.theme.color("tab.activeBackground", color(45/255, 45/255, 60/255))
  else:
    builder.theme.color("tab.inactiveBackground", color(45/255, 45/255, 45/255))

  let textColor = builder.theme.color("editor.foreground", color(0.9, 0.8, 0.8))
  let borderColor = builder.theme.color("panel.border", backgroundColor.lighten(0.2))
  let selectionColor = builder.theme.color("list.activeSelectionBackground",
    color(0.8, 0.8, 0.8)).withAlpha(1)
  let titleForegroundColor = builder.theme.color(@["selector.title.foreground", "editor.foreground"], color(0.1, 0.1, 0.1)).withAlpha(1)

  let excluded = ["prev", "next", "accept", "close"]
  proc filterCommand(s: string): bool =
    return not excluded.anyIt(s.toLowerAscii.startsWith(it))
  let nextPossibleInputs = events.getNextPossibleInputs(false, (handler) => handler.config.context.startsWith("popup.selector")).filterIt(filterCommand(it.description))
  var whichKeyHeightLines = config.getUiPopupWhichKeyHeight()
  whichKeyHeightLines = (nextPossibleInputs.len + 1) div 2
  let whichKeyHeightPx = builder.renderCommandKeysHeight(whichKeyHeightLines, padding = 0)

  builder.panel(&{FillBackground, DrawBorder, DrawBorderTerminal}, x = bounds.x, y = bounds.y, w = bounds.w, h = bounds.h, border = border(1),
      backgroundColor = backgroundColor, borderColor = borderColor, userId = self.userId.newPrimaryId):

    builder.panel(&{FillX, MaskContent, OverlappingChildren} + yFlag): #, userId = id):
      let totalLineHeight = builder.textHeight

      block:
        builder.panel(&{FillX, LayoutVertical} + yFlag, w = bounds.w * (1 - previewScale)):
          let leftBounds = currentNode.bounds

          let title = if self.title != "": self.title else: self.scope
          if title != "":
            builder.panel(&{FillX, SizeToContentY, FillBackground}, backgroundColor = headerColor):
              builder.panel(&{SizeToContentX, SizeToContentY, DrawText},
                text = title,
                pivot = vec2(0.5, 0),
                textColor = titleForegroundColor,
                x = leftBounds.w * 0.5)

          builder.panel(&{FillX, SizeToContentY}):
            result.add self.textEditor.render(builder)
            builder.updateSizeToContent(currentNode)

            builder.panel(&{FillX, FillY, LayoutHorizontalReverse}):
              if self.finder.isNotNil and self.finder.filteredItems.getSome(items):
                let text = &"{items.filteredLen}/{items.len}"
                builder.panel(&{SizeToContentX, SizeToContentY, DrawText}, text = text, textColor = textColor, pivot = vec2(1, 0))
              if self.finder.isNotNil and self.finder.filteredItems.getSome(items) and items.locked:
                builder.panel(&{SizeToContentX, SizeToContentY, DrawText}, text = "...", textColor = textColor, pivot = vec2(1, 0))
          builder.updateSizeToContent(currentNode)

          if self.finder.isNotNil and self.finder.filteredItems.getSome(items) and items.filteredLen > 0:
            let highlightColor = builder.theme.color("editor.foreground.highlight", textColor.lighten(0.18))
            let detailColor = textColor.darken(0.2)
            let detailsFontScale = config.get("ui.selector.details-font-scale", 0.85)

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
                    capture(completionIndex):
                      onClickAny btn:
                        self.selectNth(completionIndex)
                        if self.isInLayout:
                          self.accept()
                    let displayIndex = if completionIndex + 1 < 10:
                      $(completionIndex + 1)
                    elif completionIndex + 1 < 36:
                      " "
                    elif completionIndex + 1 < 62:
                      " "
                    else:
                      " "
                    row.add builder.createTextWithMaxWidth(displayIndex, maxColumnWidth, "...", detailColor, &{TextItalic}, fontScale = detailsFontScale)

                    if config.get("ui.selector.show-score", false):
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
            let textColor = builder.theme.color("editor.foreground", color(0.882, 0.784, 0.784))
            let continuesTextColor = builder.theme.tokenColor("keyword", color(0.882, 0.784, 0.784))
            let keysTextColor = builder.theme.tokenColor("number", color(0.882, 0.784, 0.784))
            var headerColor = builder.theme.color("tab.inactiveBackground", color(0.176, 0.176, 0.176))
            builder.renderCommandKeys(nextPossibleInputs, textColor, continuesTextColor, keysTextColor, headerColor, whichKeyHeightLines, currentNode.bounds, padding = 0)

        if SizeToContentY notin yFlag:
          let textColor = builder.theme.color("editor.foreground", color(0.882, 0.784, 0.784))
          let continuesTextColor = builder.theme.tokenColor("keyword", color(0.882, 0.784, 0.784))
          let keysTextColor = builder.theme.tokenColor("number", color(0.882, 0.784, 0.784))
          var headerColor = builder.theme.color("tab.inactiveBackground", color(0.176, 0.176, 0.176))
          builder.panel(&{FillX, FillY, LayoutVerticalReverse}):
            builder.panel(&{FillX, SizeToContentY}, pivot = vec2(0, 1)):
              builder.renderCommandKeys(nextPossibleInputs, textColor, continuesTextColor, keysTextColor, headerColor, whichKeyHeightLines, currentNode.bounds, padding = 0)
              builder.updateSizeToContent(currentNode)

        if showPreview:
          builder.panel(0.UINodeFlags, x = bounds.w * (1 - previewScale),
              w = bounds.w * previewScale, h = bounds.h, tag = "preview"):

            self.previewEditor.active = self.focusPreview

            if self.previewView != nil:
              result.add self.previewView.render(builder)
            elif self.previewer.isSome:
              result.add self.previewer.get.render(builder)

    if sizeToContentY:
      currentNode.h = currentNode.last.h + currentNode.border.top + currentNode.border.bottom
