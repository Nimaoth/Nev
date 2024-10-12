import std/[strformat, options, macros, genasts, strutils, math, os]
from logging import nil
import util, timer
export strformat

{.used.}
{.push raises: [].}

export logging.Level, logging.Logger, logging.defaultFmtStr, logging.addHandler

import std/[terminal, colors]
type FileLogger = logging.FileLogger

type
  CustomLogger* = ref object of logging.Logger
    indentLevel*: int
    consoleLogger: Option[logging.Logger]
    fileLogger: Option[FileLogger]
    timer: Timer

    otherLoggers: seq[logging.Logger]

proc indentString*(logger: CustomLogger): string =
  "  ".repeat(max(0, logger.indentLevel))

proc newCustomLogger*(levelThreshold = logging.lvlAll, fmtStr = logging.defaultFmtStr): CustomLogger =
  new result

  result.fmtStr = fmtStr
  result.levelThreshold = levelThreshold
  logging.addHandler(result)

  result.timer = startTimer()

proc enableFileLogger*(self: CustomLogger, filename = "logs/messages.log") =
  let filename = if filename.isAbsolute:
    filename
  else:
    getAppDir() / filename
  var file = open(filename, fmWrite).catch:
    return
  self.fileLogger = logging.newFileLogger(file, self.levelThreshold, "", flushThreshold=logging.lvlAll).some

proc enableConsoleLogger*(self: CustomLogger) =
  self.consoleLogger = logging.Logger(logging.newConsoleLogger(self.levelThreshold, "", flushThreshold=logging.lvlAll)).some

proc setConsoleLogger*(self: CustomLogger, logger: logging.Logger) =
  self.consoleLogger = logger.some

proc addLogger*(self: CustomLogger, logger: logging.Logger) =
  self.otherLoggers.add logger

proc toggleConsoleLogger*(self: CustomLogger) =
  if self.consoleLogger.isSome:
    self.consoleLogger = logging.Logger.none
  else:
    self.enableConsoleLogger()

let isTerminal {.used.} = when declared(isatty): isatty(stdout) else: false

func formatTime(t: float64): string =
  if t >= 1000:
    return &"{int(t / 1000)}s {(t mod 1000.0):>6.2f}ms"
  return &"{t:6.3f}ms"

method log(self: CustomLogger, level: logging.Level, args: varargs[string, `$`]) =
  let time = self.timer.elapsed.ms
  let msgIndented = self.indentString & logging.substituteLog("", level, args)
  let fmtStr = &"[{formatTime(time)}] " & self.fmtStr
  let msg = logging.substituteLog(fmtStr, level, msgIndented)

  for l in self.otherLoggers:
    try:
      {.gcsafe.}:
        logging.log(l, level, msg)
    except:
      continue

  if self.fileLogger.getSome(l):
    try:
      {.gcsafe.}:
        logging.log(l, level, msg)
    except:
      discard

  if self.consoleLogger.getSome(l):
    if isTerminal:
      let color = case level
      of logging.lvlDebug: rgb(100, 100, 200)
      of logging.lvlInfo: rgb(200, 200, 200)
      of logging.lvlNotice: rgb(200, 255, 255)
      of logging.lvlWarn: rgb(200, 200, 100)
      of logging.lvlError: rgb(255, 150, 150)
      of logging.lvlFatal: rgb(255, 0, 0)
      else: rgb(255, 255, 255)
      try:
        {.gcsafe.}:
          stdout.write(ansiForegroundColorCode(color))
      except IOError:
        discard

    try:
      {.gcsafe.}:
        logging.log(l, level, msg)
    except:
      discard

    if isTerminal:
      try:
        {.gcsafe.}:
          stdout.write(ansiForegroundColorCode(rgb(255, 255, 255)))
      except IOError:
        discard

var logger* = newCustomLogger()

proc flush*(logger: logging.Logger) =
  if logger of FileLogger:
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
      try:
        {.gcsafe.}:
          logging.log(level, args)
      except:
        discard

  macro log(level: logging.Level, args: varargs[untyped, `$`]): untyped {.used.} =
    return logImpl(level, args, true)

  macro logNoCategory(level: logging.Level, args: varargs[untyped, `$`]): untyped {.used.} =
    return logImpl(level, args, false)

  template measureBlock(description: string, body: untyped): untyped {.used.} =
    let timer = startTimer()
    body
    block:
      let descriptionString = description
      try:
        {.gcsafe.}:
          logging.log(lvlInfo, "[" & category & "] " & descriptionString & " took " & $timer.elapsed.ms & " ms")
      except:
        discard

  template logScope(level: logging.Level, text: string): untyped {.used.} =
    let txt = text
    {.gcsafe.}:
      try:
        logging.log(level, "[" & category & "] " & txt)
      except:
        discard
      inc logger.indentLevel
      let timer = startTimer()
      defer:
        block:
          let elapsedMs = timer.elapsed.ms
          let split = elapsedMs.splitDecimal
          let elapsedMsInt = split.intpart.int
          let elapsedUsInt = (split.floatpart * 1000).int
          dec logger.indentLevel
          assert logger.indentLevel >= 0, "Indent level going < 0 for " & $level & " [" & category & "] " & txt
          try:
            {.gcsafe.}:
              logging.log(level, "[" & category & "] " & txt & " finished. (" & $elapsedMsInt & " ms " & $elapsedUsInt & " us)")
          except:
            discard

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