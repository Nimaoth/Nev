import std/[options, strutils, sugar, sequtils]
import vmath, bumpy, chroma
import misc/[util, custom_logger, disposable_ref]
import platform
import selector_popup, theme, document_editor, core_settings
import finder, previewer
import config_provider, input_handler/input_handler, view
import service
import nuigi
import nuigi/widgets
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

    # NUI-GAP: old index column shows $(i+1) only for i+1<10 else " " (blank for
    # 10..61+), via createTextWithMaxWidth(maxColumnWidth, detailColor, italic,
    # detailsFontScale); new always shows the number (10, 11, ...) in
    # MenuItem[Hover]Text (see §24).
    b.node:
      discard b.fit().backendPadding(2)
        .textStyleIndex(int(if selected:
          UiStyleIndexMenuItemHoverText
        else:
          UiStyleIndexMenuItemText))
        .text($(itemIndex + 1))

    if storage.showScore:
      b.node:
        discard b.fit().backendPadding(2)
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
      discard b.fit().backendPadding(2).maskChildren()
      b.highlightedText(item.displayName, matchIndices, labelColor,
        highlightColor, popup.maxDisplayNameWidth)

    # NUI-GAP: old details render one column per detail via
    # createTextWithMaxWidth(detail, maxColumnWidth, detailColor, italic,
    # detailsFontScale=config ui.selector.details-font-scale 0.85); new joins
    # all details into one SmallText column, no max-width/italic/scale (see §24).
    # NUI-GAP: old grid post-pass aligns columns (maxWidths/maxHeights, gap of
    # 1*charWidth, vertical centering); new relies on listTable fixed/
    # proportional widths + columnGap 6/1 (see §24).
    b.node:
      discard b.fit().backendPadding(2).maskChildren()
        .textStyleIndex(int(UiStyleIndexSmallText))
        .text(item.details.join("  "))

    # NUI-GAP: old row click is capture(completionIndex)+onClickAny (any button,
    # absolute cachedScrollOffset+i index); new wasClicked has different gesture
    # semantics and relies on virtual-list itemIndex (see §24).
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
          discard nui.fillX().fillY().backendGap(2)
          let title = if self.title.len > 0: self.title else: self.scope
          if title.len > 0:
            nui.node("selector-popup-title"):
              discard nui.fillX().fitY().backendPadding(4)
                .styleIndex(UiStyleIndexHeader).fillBackground()
                .textStyleIndex(int(UiStyleIndexHeaderText)).text(title)

          # Search editor sizes to its content via the text editor fitY mode
          # (single line, header hidden); no fixed height pin.
          nui.node("selector-popup-search"):
            discard nui.fillX().fitY().maskChildren()
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
            # NUI-GAP: old scrolling keeps scrollOffset/lastRenderedIndex math
            # (maxLineCount 30 or floor((rowsH-whichKeyPx)/lineH), clamp, asserts),
            # reuses cachedFinderItems when items.locked, handles onScroll and draws
            # a custom scrollbar; new only ensureItemVisible + listTable default
            # (see §24).
            if self.scrollToSelected and storage.listStorage != nil and
                storage.listStorage.ensureItemVisible(
                  self.selected, storage.listStorage.viewportHeight, 0):
              self.scrollToSelected = false

          nui.layoutHorizontal("selector-popup-status"):
            discard nui.fillX().fitY().backendPaddingY(2).backendGap(4)
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
            .styleIndex(UiStyleIndexPanel).fillBackground().backendPadding(4)
            .maskChildren()
          if self.previewView != nil:
            self.previewView.render(nui)
          elif self.previewer.isSome and self.previewer.get.renderNuiImpl != nil:
            self.previewer.get.renderNui(nui)
          elif self.previewEditor != nil:
            self.previewEditor.renderNui(nui)

  # NUI-GAP: old popup chrome dims inactive/focusPreview (inactiveBrightnessChange,
  # popupBrightnessChange), honors getUiBackgroundTransparent, draws DrawBorder(1)
  # with panel.border color + userId=newPrimaryId; new always UiStyleIndexMenu
  # with no border/transparency/active dimming (see §24).
  # NUI-GAP: old selector-local which-key footer (renderCommandKeys with
  # prev/next/accept/close filter) has no NUI equivalent; new shows only the
  # count/"..." status row (see §24).
  if self.isInLayout:
    nui.node("selector-popup"):
      discard nui.fillX().fillY().styleIndex(UiStyleIndexMenu)
        .fillBackground().backendPadding(4, 1).maskChildren()
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
        discard nui.styleIndex(UiStyleIndexMenu).fillBackground().backendPadding(4, 1)
          .maskChildren()
        buildPopupContents()
