import std/[json, strformat, strutils, tables, options]
import os
import compiler/options as copts

import nimscripter, nimscripter/[vmconversion, vmaddins]

type ScriptContext* = ref object
  inter*: Option[Interpreter]
  script: NimScriptPath
  addins: VMAddins

let stdPath = "C:/Users/nimao/.choosenim/toolchains/nim-#devel/lib"

proc errorHook(config: ConfigRef; info: TLineInfo; msg: string; severity: Severity) {.gcsafe.} =
  if (severity == Error or severity == Warning) and config.errorCounter >= config.errorMax:
    var fileName: string
    for k, v in config.m.filenameToIndexTbl.pairs:
      if v == info.fileIndex:
        fileName = k
    echo fmt"[vm {severity}]: $1:$2:$3 $4." % [fileName, $info.line, $(info.col + 1), msg]
    raise (ref VMQuit)(info: info, msg: msg)

proc setGlobalVariable*[T](intr: Option[Interpreter] or Interpreter; name: string, value: T) =
  ## Easy access of a global nimscript variable
  when intr is Option[Interpreter]:
    assert intr.isSome
    let intr = intr.get
  let sym = intr.selectUniqueSymbol(name)
  if sym != nil:
    intr.setGlobalValue(sym, toVm(value))
  else:
    raise newException(VmSymNotFound, name & " is not a global symbol in the script.")

proc newScriptContext*(path: string, addins: VMAddins): ScriptContext =
  new result
  result.script = NimScriptPath(path)
  result.addins = addins
  result.inter = loadScript(result.script, addins, "scripting_api", stdPath = stdPath, searchPaths = @["src"], vmErrorHook = errorHook)

proc reloadScript*(ctx: ScriptContext) =
  ctx.inter.safeLoadScriptWithState(ctx.script, ctx.addins, "scripting_api", stdPath = stdPath, searchPaths = @["src"], vmErrorHook = errorHook)

when false:
  proc doThing(): int = 41
  proc log(str: string) = echo "[nim] ", str

  exportTo(myImpl, doThing, log)

  addCallable(myImpl):
    proc logScript(str: string)
  const
    scriptProcs = implNimScriptModule(myImpl)
    ourScript = NimScriptPath("script.nims")

  echo scriptProcs
  let intr = loadScript(ourScript, scriptProcs, stdPath = stdPath, vmErrorHook = errorHook)

  intr.invoke(logScript, "hi")

  getGlobalNimsVars intr:
    a: bool
    b: string
    c: int
    d: TestType
    e: TestType2

  echo a
  echo b
  echo c
  echo d
  print e

  var d2 = d
  d2.a += 2
  d2.b = "hi"
  d2.c[6] = "six"
  intr.setGlobalVariable("d", d2)

  intr.invoke(run)