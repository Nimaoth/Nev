import std/[strformat, strutils, os]

const nevModuleName {.strdefine.}: string = ""
const implModule = nevModuleName == "nev"

when defined(useDynlib):
  when implModule:
    # We are compiling the file containing the implementations
    {.pragma: rtl, exportc, dynlib.}
    {.pragma: apprtl, exportc, dynlib.}
    {.pragma: rtlImport, exportc, dynlib.}
    {.pragma: rtlImpl.}
  else:
    # We are compiling the file importing the declarations
    {.pragma: rtl, importc, dynlib: "nev.exe".}
    {.pragma: rtlImport, importc, dynlib: "nev.exe".}
    {.pragma: apprtl, importc, dynlib: "nev.exe".}
else:
  # We are linking statically
  {.pragma: apprtl.}
  {.pragma: rtlImport, importc.}
  {.pragma: rtlImpl, exportc.}
