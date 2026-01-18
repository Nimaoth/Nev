import std/[strutils, os]

const nevModuleName {.strdefine.}: string = ""
const nevDeps {.strdefine.}: string = ""
const nevDepsA = nevDeps.split(",")

proc getCurrentModuleName(): string {.compiletime.} =
  let p = currentSourcePath2
  return p.splitFile.name
const currentModuleName = getCurrentModuleName()

const implModule = not defined(useDynlib) or currentModuleName == nevModuleName

when defined(useDynlib):
  when currentModuleName == nevModuleName:
    # We are compiling the file containing the implementations
    {.pragma: rtl, exportc, dynlib, cdecl.}
  elif nevDepsA.contains(currentModuleName):
    # We are compiling the file importing the declarations
    {.pragma: rtl, importc, dynlib: "modules/" & currentModuleName & ".dll", cdecl.}
  else:
    import std/[strformat]
    {.error: &"{currentModuleName} is not defined as dependency for {nevModuleName}".}
else:
  # We are linking statically
  {.pragma: rtl, cdecl.}
