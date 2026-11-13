import std/options
import platform, core_settings, nuigi
from nuigi/widgets import button

type
  ViewPanelCloseAction* = proc(keepHidden: bool) {.closure, gcsafe, raises: [].}
  ViewPanelAction* = proc() {.closure, gcsafe, raises: [].}

  ViewPanelOptions* = object
    ## Layout options for `viewPanel`. Padding and gaps must be known before the
    ## header is built, so they can't be changed from the body.
    fitContentY*: bool
    padding*: float32 = 1
    gap*: float32 = 4
    cornerRadius*: float32 = 8
    headerCornerRadius*: Option[float32] = none(float32)
    contentCornerRadius*: Option[float32] = none(float32)
    headerPadding*: float32 = 6
    headerGap*: float32 = 4
    headerContentGap*: float32 = 4
    headerActionsGap*: float32 = 4
    contentPadding*: float32 = 4
    cacheSubtree*: bool = false
    cacheDirty*: bool = false
    onClose*: ViewPanelCloseAction
      ## View action; true hides the view, false closes it. Invoked next frame.
    onSplitVertical*: ViewPanelAction
      ## Split with a vertical divider. Invoked next frame.
    onSplitHorizontal*: ViewPanelAction
      ## Split with a horizontal divider. Invoked next frame.

proc enqueueViewPanelAction(builder: var UiBuilder, action: ViewPanelCloseAction,
    keepHidden: bool) {.gcsafe, raises: [].} =
  builder.enqueueNextFrame(proc() {.closure, gcsafe, raises: [].} =
    action(keepHidden))

proc enqueueViewPanelAction(builder: var UiBuilder, action: ViewPanelAction)
    {.gcsafe, raises: [].} =
  builder.enqueueNextFrame(action)

type ViewPanelCacheStorage = ref object of UiNodeStorageData
  hovered: bool
  animating: bool
  active: bool
  showHeader: bool
  options: ViewPanelOptions
  styles: seq[UiStyle]
  textStyles: seq[UiNodeText]

proc recordViewPanelAnimation(builder: var UiBuilder, nodeIndex, rootIndex: int)
    {.nimcall, gcsafe, raises: [].} =
  let storage = cast[ViewPanelCacheStorage](
    builder.nodeStorageGet(builder.frame.nodes[rootIndex].addr))
  storage.animating = builder.anythingAnimating

proc reuseViewPanel(builder: var UiBuilder, active, showHeader: bool,
    options: ViewPanelOptions): bool {.gcsafe, raises: [].} =
  var storage = cast[ViewPanelCacheStorage](builder.nodeStorageGet(builder.currentNode))
  if storage == nil:
    storage = ViewPanelCacheStorage()
    builder.nodeStorage(builder.currentNode, storage)
  let hovered = builder.wasHovered(includeChildren = true)
  let input = builder.frameCtx.input
  let dirty = options.cacheDirty or hovered or storage.hovered or storage.animating or
    input.mouseDown != {} or input.mousePressed != {} or input.mouseReleased != {} or
    active != storage.active or showHeader != storage.showHeader or
    options.fitContentY != storage.options.fitContentY or
    options.padding != storage.options.padding or options.gap != storage.options.gap or
    options.cornerRadius != storage.options.cornerRadius or
    options.headerCornerRadius != storage.options.headerCornerRadius or
    options.contentCornerRadius != storage.options.contentCornerRadius or
    options.headerPadding != storage.options.headerPadding or
    options.headerGap != storage.options.headerGap or
    options.headerContentGap != storage.options.headerContentGap or
    options.headerActionsGap != storage.options.headerActionsGap or
    options.contentPadding != storage.options.contentPadding or
    (options.onClose == nil) != (storage.options.onClose == nil) or
    (options.onSplitVertical == nil) != (storage.options.onSplitVertical == nil) or
    (options.onSplitHorizontal == nil) != (storage.options.onSplitHorizontal == nil) or
    builder.themeStyles != storage.styles or builder.themeTextStyles != storage.textStyles
  storage.hovered = hovered
  storage.active = active
  storage.showHeader = showHeader
  storage.options = options
  if builder.themeStyles != storage.styles:
    storage.styles = @[]
    for style in builder.themeStyles:
      storage.styles.add style
  if builder.themeTextStyles != storage.textStyles:
    storage.textStyles = @[]
    for style in builder.themeTextStyles:
      storage.textStyles.add style
  builder.reuseCachedNode(dirty)

proc withConfiguredViewPanelSettings(config: ConfigStore,
    options: ViewPanelOptions): ViewPanelOptions =
  result = options
  result.padding = config.getUiViewPanelPadding(options.padding.float).float32
  result.gap = config.getUiViewPanelGap(options.gap.float).float32
  result.cornerRadius = config.getUiViewPanelCornerRadius(options.cornerRadius.float).float32
  result.headerCornerRadius = some(config.getUiViewPanelHeaderCornerRadius(
    options.headerCornerRadius.get(options.cornerRadius - options.padding).float).float32)
  result.contentCornerRadius = some(config.getUiViewPanelContentCornerRadius(
    options.contentCornerRadius.get(options.cornerRadius).float).float32)
  result.headerPadding = config.getUiViewPanelHeaderPadding(options.headerPadding.float).float32
  result.headerGap = config.getUiViewPanelHeaderGap(options.headerGap.float).float32
  result.headerContentGap = config.getUiViewPanelHeaderContentGap(options.headerContentGap.float).float32
  result.headerActionsGap = config.getUiViewPanelHeaderActionsGap(options.headerActionsGap.float).float32
  result.contentPadding = config.getUiViewPanelContentPadding(options.contentPadding.float).float32

template viewPanel*(builder: var UiBuilder, key: string, active: bool,
    showHeader: bool, options: ViewPanelOptions, header, buttons, body: untyped) =
  ## Root of a view: a vertical layout using the (active) panel style with an
  ## optional header bar using the (active) header style above the body.
  ## `header` is injected inside the horizontal header node (only when `showHeader`),
  ## `buttons` is injected before Split/Hide/Close in the hover-only top-right action row.
  ## `body` is injected inside the root node after the header.
  block:
    let viewPanelKey = key
    let viewPanelActive = active
    let viewPanelOptions = options
    builder.layoutVertical(viewPanelKey):
      discard builder.fillX().fillBackground().styleIndex(
        if viewPanelActive: UiStyleIndexPanelActive else: UiStyleIndexPanel)
        .backendPadding(viewPanelOptions.padding).backendGap(viewPanelOptions.gap)
        .cornerRadius(viewPanelOptions.cornerRadius)
      if viewPanelOptions.fitContentY:
        discard builder.fitY()
      else:
        discard builder.fillY()
      block viewPanelContents:
        if viewPanelOptions.cacheSubtree and
            builder.reuseViewPanel(viewPanelActive, showHeader, viewPanelOptions):
          break viewPanelContents
        if showHeader:
          let headerCornerRadius = viewPanelOptions.headerCornerRadius.get(
            viewPanelOptions.cornerRadius - viewPanelOptions.padding)
          builder.layoutHorizontalReverse(viewPanelKey & "-header"):
            discard builder.fillX().fitY().fillBackground().styleIndex(
              if viewPanelActive: UiStyleIndexHeaderActive else: UiStyleIndexHeader)
              .backendPadding(viewPanelOptions.headerPadding).backendGap(viewPanelOptions.headerGap)
              .cornerRadius(0)
              .cornerRadii(headerCornerRadius, headerCornerRadius, 0, 0)
            if builder.wasHovered(includeChildren = true):
              builder.layoutHorizontal(viewPanelKey & "-buttons"):
                # Reserve horizontal space without letting hover actions resize the header.
                discard builder.fit().backendGap(viewPanelOptions.headerActionsGap)
                  .ignoreInContentExtent()
                  .anchorsY(0.5, 0.5).pivotY(0.5).finishAnchors()
                buttons
                if viewPanelOptions.onSplitVertical != nil:
                  if builder.button("|"):
                    builder.enqueueViewPanelAction(viewPanelOptions.onSplitVertical)
                if viewPanelOptions.onSplitHorizontal != nil:
                  if builder.button("="):
                    builder.enqueueViewPanelAction(viewPanelOptions.onSplitHorizontal)
                if viewPanelOptions.onClose != nil:
                  if builder.button("-"):
                    builder.enqueueViewPanelAction(viewPanelOptions.onClose, true)
                  if builder.button("x"):
                    builder.enqueueViewPanelAction(viewPanelOptions.onClose, false)
            builder.layoutHorizontal(viewPanelKey & "-header-content"):
              discard builder.fillX().fitY().backendGap(viewPanelOptions.headerContentGap)
                .maskChildren()
              header
        builder.node(viewPanelKey & "-content"):
          discard builder.fillX().cornerRadius(0).cornerRadii(0, 0,
            viewPanelOptions.contentCornerRadius.get(viewPanelOptions.cornerRadius),
            viewPanelOptions.contentCornerRadius.get(viewPanelOptions.cornerRadius))
            .backendPadding(viewPanelOptions.contentPadding)
          if viewPanelOptions.fitContentY:
            discard builder.fitY()
          else:
            discard builder.fillY()
          body
        if viewPanelOptions.cacheSubtree:
          let rootIndex = builder.currentNodeIndex
          builder.node:
            discard builder.size(0, 0).position(0, 0).ignoreInContentExtent()
              .noHover().deferBuild(recordViewPanelAnimation, rootIndex)

template viewPanel*(builder: var UiBuilder, key: string, active: bool,
    showHeader: bool, options: ViewPanelOptions, header, body: untyped) =
  builder.viewPanel(key, active, showHeader, options, header, (discard), body)

template viewPanel*(builder: var UiBuilder, key: string, active: bool,
    showHeader: bool, header, buttons, body: untyped) =
  builder.viewPanel(key, active, showHeader, ViewPanelOptions(), header, buttons, body)

template viewPanel*(builder: var UiBuilder, key: string, active: bool,
    showHeader: bool, header: untyped, body: untyped) =
  builder.viewPanel(key, active, showHeader, ViewPanelOptions(), header, body)

template viewPanel*(builder: var UiBuilder, key: string, active: bool,
    showHeader: bool, config: ConfigStore, options: ViewPanelOptions,
    header, buttons, body: untyped) =
  builder.viewPanel(key, active, showHeader,
    withConfiguredViewPanelSettings(config, options), header, buttons, body)

template viewPanel*(builder: var UiBuilder, key: string, active: bool,
    showHeader: bool, config: ConfigStore, options: ViewPanelOptions,
    header, body: untyped) =
  builder.viewPanel(key, active, showHeader,
    withConfiguredViewPanelSettings(config, options), header, body)

template viewPanel*(builder: var UiBuilder, key: string, active: bool,
    showHeader: bool, config: ConfigStore, header, buttons, body: untyped) =
  builder.viewPanel(key, active, showHeader, config, ViewPanelOptions(),
    header, buttons, body)

template viewPanel*(builder: var UiBuilder, key: string, active: bool,
    showHeader: bool, config: ConfigStore, header: untyped, body: untyped) =
  builder.viewPanel(key, active, showHeader, config, ViewPanelOptions(),
    header, body)
