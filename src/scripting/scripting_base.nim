
import custom_logger

type ScriptContext* = ref object of RootObj
  discard

method init*(self: ScriptContext, path: string) {.base.} = discard

method reload*(self: ScriptContext) {.base.} = discard