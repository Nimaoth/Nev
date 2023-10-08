import std/[strformat, options, macros, genasts]
from logging import nil
import util
export strformat

{.used.}

export logging.Level, logging.Logger, logging.defaultFmtStr, logging.addHandler

when not defined(js):
  import std/[terminal, colors]
  type FileLogger = logging.FileLogger
else:
  type FileLogger = ref object of logging.Logger
    discard

type
  CustomLogger* = ref object of logging.Logger
    consoleLogger: Option[logging.ConsoleLogger]
    fileLogger: Option[FileLogger]

proc newCustomLogger*(levelThreshold = logging.lvlAll, fmtStr = logging.defaultFmtStr): CustomLogger =
  new result
  result.fmtStr = fmtStr
  result.levelThreshold = levelThreshold
  logging.addHandler(result)

proc enableFileLogger*(self: CustomLogger) =
  when not defined(js):
    var file = open("messages.log", fmWrite)
    self.fileLogger = logging.newFileLogger(file, self.levelThreshold, self.fmtStr, flushThreshold=logging.lvlAll).some

proc enableConsoleLogger*(self: CustomLogger) =
  self.consoleLogger = logging.newConsoleLogger(self.levelThreshold, self.fmtStr, flushThreshold=logging.lvlAll).some

let isTerminal {.used.} = when declared(isatty): isatty(stdout) else: false

method log(self: CustomLogger, level: logging.Level, args: varargs[string, `$`]) =
  if self.fileLogger.getSome(l):
    logging.log(l, level, args)

  if self.consoleLogger.getSome(l):
    when not defined(js):
      if isTerminal:
        let color = case level
        of lvlDebug: rgb(100, 100, 200)
        of lvlInfo: rgb(200, 200, 200)
        of lvlNotice: rgb(200, 255, 255)
        of lvlWarn: rgb(200, 200, 100)
        of lvlError: rgb(255, 150, 150)
        of lvlFatal: rgb(255, 0, 0)
        else: rgb(255, 255, 255)
        stdout.write(ansiForegroundColorCode(color))

    logging.log(l, level, args)

    when not defined(js):
      if isTerminal:
        stdout.write(ansiForegroundColorCode(rgb(255, 255, 255)))

var logger* = newCustomLogger()

proc flush*(logger: logging.Logger) =
  if logger of FileLogger:
    when not defined(js):
      logger.FileLogger.file.flushFile()
  elif logger of CustomLogger and logger.CustomLogger.fileLogger.getSome(l):
    l.flush()

proc substituteLog*(frmt: string, level: logging.Level,
                    args: varargs[string, `$`]): string =
  logging.substituteLog(frmt, level, args)

template logCategory*(category: static string, noDebug = false): untyped =
  proc logImpl(level: NimNode, args: NimNode, includeCategory: bool): NimNode {.used.} =
    var args = args
    if includeCategory:
      args.insert(0, newLit("[" & category & "] "))

    return genAst(level, args):
      logging.log(level, args)

  macro log(level: logging.Level, args: varargs[untyped, `$`]): untyped {.used.} =
    return logImpl(level, args, true)

  macro logNoCategory(level: logging.Level, args: varargs[untyped, `$`]): untyped {.used.} =
    return logImpl(level, args, false)

  when noDebug:
    macro debug(x: varargs[typed, `$`]): untyped {.used.} =
      discard

    macro debugf(x: static string): untyped {.used.} =
      discard

  else:
    macro debug(x: varargs[typed, `$`]): untyped {.used.} =
      let level = genAst(): lvlDebug
      let arg = genAst(x):
        x.join ""
      return logImpl(level, nnkArgList.newTree(arg), true)

    macro debugf(x: static string): untyped {.used.} =
      let level = genAst(): lvlDebug
      let arg = genAst(str = x):
        fmt str
      return logImpl(level, nnkArgList.newTree(arg), true)