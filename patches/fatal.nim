#
#
#            Nim's Runtime Library
#        (c) Copyright 2019 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

{.push profiler: off.}

const
  gotoBasedExceptions = compileOption("exceptions", "goto")
  quirkyExceptions = compileOption("exceptions", "quirky")

when hostOS == "standalone":
  include "$projectpath/panicoverride"

  func sysFatal(exceptn: typedesc[Defect], message: string) {.inline.} =
    panic(message)

  func sysFatal(exceptn: typedesc[Defect], message, arg: string) {.inline.} =
    rawoutput(message)
    panic(arg)

elif quirkyExceptions and not defined(nimscript):
  import ansi_c

  func name(t: typedesc): string {.magic: "TypeTrait".}

  func sysFatal(exceptn: typedesc[Defect], message, arg: string) {.inline, noreturn.} =
    when nimvm:
      # TODO when doAssertRaises works in CT, add a test for it
      raise (ref exceptn)(msg: message & arg)
    else:
      {.noSideEffect.}:
        writeStackTrace()
        var buf = newStringOfCap(200)
        add(buf, "Error: unhandled exception: ")
        add(buf, message)
        add(buf, arg)
        add(buf, " [")
        add(buf, name exceptn)
        add(buf, "]\n")
        cstderr.rawWrite buf
      rawQuit 1

  func sysFatal(exceptn: typedesc[Defect], message: string) {.inline, noreturn.} =
    sysFatal(exceptn, message, "")

else:
  ##### patch begin - Can't call writeStackTrace here directly, call a c function defined in absytree.nim
  when defined(enableSysFatalStackTrace) and not defined(wasm):
    proc writeStackTrace2() {.importc: "writeStackTrace2".}
  ##### patch end

  func sysFatal(exceptn: typedesc[Defect], message: string) {.inline, noreturn.} =
    ##### patch begin - I want that stacktrace
    when defined(enableSysFatalStackTrace) and not defined(wasm):
      writeStackTrace2()
    ##### patch end
    raise (ref exceptn)(msg: message)

  func sysFatal(exceptn: typedesc[Defect], message, arg: string) {.inline, noreturn.} =
    ##### patch begin - I want that stacktrace
    when defined(enableSysFatalStackTrace) and not defined(wasm):
      writeStackTrace2()
    ##### patch end
    raise (ref exceptn)(msg: message & arg)

{.pop.}
