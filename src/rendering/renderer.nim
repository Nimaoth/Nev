import widgets

type
  Renderer* = ref object of RootObj
    discard

method render*(self: Renderer, widget: WWidget) {.base.} = discard

