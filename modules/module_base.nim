
{.push, hint[DuplicateModuleImport]: off.}
import std/[strutils, os]
{.pop.}

const nevModuleName {.strdefine.}: string = ""

proc getCurrentModuleName(): string {.compiletime.} =
  let p = currentSourcePath2
  return p.splitFile.name
const currentModuleName = getCurrentModuleName()

const implModule = not defined(useDynlib) or currentModuleName == nevModuleName

when defined(useDynlib):
  when currentModuleName == nevModuleName:
    # We are compiling the file containing the implementations
    {.pragma: rtl, exportc, dynlib, cdecl.}
  else:
    const nevDeps {.strdefine.}: string = ""
    const nevDepsA = nevDeps.split(",")
    when nevModuleName == "nev" or nevDepsA.contains(currentModuleName):
      # We are compiling the file importing the declarations
      {.pragma: rtl, importc, dynlib: "native_plugins/" & currentModuleName & ".dll", cdecl.}
    else:
      import std/[strformat]
      {.error: &"{currentModuleName} is not defined as dependency for {nevModuleName}".}
else:
  # We are linking statically
  {.pragma: rtl, cdecl.}
