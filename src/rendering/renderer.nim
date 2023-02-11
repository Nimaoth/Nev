import widgets, ../event, ../input
import vmath

type
  Renderer* = ref object of RootObj
    redrawEverything*: bool
    onKeyPress*: Event[tuple[input: int64, modifiers: Modifiers]]
    onKeyRelease*: Event[tuple[input: int64, modifiers: Modifiers]]
    onRune*: Event[tuple[input: int64, modifiers: Modifiers]]
    onMousePress*: Event[tuple[button: MouseButton, modifiers: Modifiers, pos: Vec2]]
    onMouseRelease*: Event[tuple[button: MouseButton, modifiers: Modifiers, pos: Vec2]]
    onMouseMove*: Event[tuple[pos: Vec2, delta: Vec2, modifiers: Modifiers, buttons: set[MouseButton]]]
    onScroll*: Event[tuple[pos: Vec2, scroll: Vec2, modifiers: Modifiers]]

method render*(self: Renderer, widget: WWidget) {.base.} = discard
method sizeChanged*(self: Renderer): bool {.base.} = discard
method size*(self: Renderer): Vec2 {.base.} = discard
method init*(self: Renderer) {.base.} = discard
method deinit*(self: Renderer) {.base.} = discard
method processEvents*(self: Renderer): int {.base.} = discard

