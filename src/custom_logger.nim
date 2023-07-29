
import std/[strformat, options]
import logging, util
export logging, strformat

{.used.}

when not defined(js):
  type FileLogger = logging.FileLogger
else:
  type FileLogger = ref object of Logger
    discard

type
  CustomLogger* = ref object of Logger
    consoleLogger: Option[ConsoleLogger]
    fileLogger: Option[FileLogger]

proc newCustomLogger*(levelThreshold = lvlAll, fmtStr = defaultFmtStr): CustomLogger =
  new result
  result.fmtStr = fmtStr
  result.levelThreshold = levelThreshold
  addHandler(result)

proc enableFileLogger*(self: CustomLogger) =
  when not defined(js):
    var file = open("messages.log", fmWrite)
    self.fileLogger = newFileLogger(file, self.levelThreshold, self.fmtStr, flushThreshold=lvlAll).some

proc enableConsoleLogger*(self: CustomLogger) =
  self.consoleLogger = newConsoleLogger(self.levelThreshold, self.fmtStr, flushThreshold=lvlAll).some

method log*(self: CustomLogger, level: Level, args: varargs[string, `$`]) =
  if self.fileLogger.getSome(l):
    l.log(level, args)
  if self.consoleLogger.getSome(l):
    l.log(level, args)

var logger* = newCustomLogger()

proc flush*(logger: Logger) =
  if logger of FileLogger:
    when not defined(js):
      logger.FileLogger.file.flushFile()
  elif logger of CustomLogger and logger.CustomLogger.fileLogger.getSome(l):
    l.flush()

template debug*(x: varargs[typed, `$`]) =
  log(lvlDebug, x.join "")

template debugf*(x: static string) =
  log(lvlDebug, fmt x)