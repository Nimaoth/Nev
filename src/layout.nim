import std/[tables, options, json]
import bumpy
import results
import platform/platform
import misc/[custom_async, custom_logger, rect_utils, myjsonutils]
import scripting/expose
import service, platform_service, dispatch_tables

{.push gcsafe.}
{.push raises: [].}

logCategory "layout"

type
  Layout* = ref object of RootObj
  HorizontalLayout* = ref object of Layout
  VerticalLayout* = ref object of Layout
  FibonacciLayout* = ref object of Layout

  LayoutProperties = ref object
    props: Table[string, float32]

  LayoutService* = ref object of Service
    platform: Platform
    layout*: Layout
    layoutProps*: LayoutProperties
    maximizeView*: bool

func serviceName*(_: typedesc[LayoutService]): string = "LayoutService"

addBuiltinService(LayoutService, PlatformService)

method init*(self: LayoutService): Future[Result[void, ref CatchableError]] {.async: (raises: []).} =
  log lvlInfo, &"LayoutService.init"
  self.platform = self.services.getService(PlatformService).get.platform
  self.layout = HorizontalLayout()
  self.layout_props = LayoutProperties(props: {"main-split": 0.5.float32}.toTable)
  return ok()

method layoutViews*(layout: Layout, props: LayoutProperties, bounds: Rect, views: int): seq[Rect] {.base.} =
  return @[bounds]

method layoutViews*(layout: HorizontalLayout, props: LayoutProperties, bounds: Rect, views: int): seq[Rect] =
  let mainSplit = props.props.getOrDefault("main-split", 0.5)
  result = @[]
  var rect = bounds
  for i in 0..<views:
    let ratio = if i == 0 and views > 1: mainSplit else: 1.0 / (views - i).float32
    let (view_rect, remaining) = rect.splitV(ratio.percent)
    rect = remaining
    result.add view_rect

method layoutViews*(layout: VerticalLayout, props: LayoutProperties, bounds: Rect, views: int): seq[Rect] =
  let mainSplit = props.props.getOrDefault("main-split", 0.5)
  result = @[]
  var rect = bounds
  for i in 0..<views:
    let ratio = if i == 0 and views > 1: mainSplit else: 1.0 / (views - i).float32
    let (view_rect, remaining) = rect.splitH(ratio.percent)
    rect = remaining
    result.add view_rect

method layoutViews*(layout: FibonacciLayout, props: LayoutProperties, bounds: Rect, views: int): seq[Rect] =
  let mainSplit = props.props.getOrDefault("main-split", 0.5)
  result = @[]
  var rect = bounds
  for i in 0..<views:
    let ratio = if i == 0 and views > 1: mainSplit elif i == views - 1: 1.0 else: 0.5
    let (view_rect, remaining) = if i mod 2 == 0: rect.splitV(ratio.percent) else: rect.splitH(ratio.percent)
    rect = remaining
    result.add view_rect

###########################################################################

proc getEditor(): Option[LayoutService] =
  {.gcsafe.}:
    if gServices.isNil: return LayoutService.none
    return gServices.getService(LayoutService)

static:
  addInjector(LayoutService, getEditor)

proc setLayout*(self: LayoutService, layout: string) {.expose("layout").} =
  self.layout = case layout
    of "horizontal": HorizontalLayout()
    of "vertical": VerticalLayout()
    of "fibonacci": FibonacciLayout()
    else: FibonacciLayout()
  self.platform.requestRender()

proc changeLayoutProp*(self: LayoutService, prop: string, change: float32) {.expose("layout").} =
  self.layout_props.props.mgetOrPut(prop, 0) += change
  self.platform.requestRender(true)

proc toggleMaximizeView*(self: LayoutService) {.expose("layout").} =
  self.maximizeView = not self.maximizeView
  self.platform.requestRender()

genDispatcher("layout")
addGlobalDispatchTable "layout", genDispatchTable("layout")

proc dispatchEvent*(action: string, args: JsonNode): Option[JsonNode] =
  dispatch(action, args)
