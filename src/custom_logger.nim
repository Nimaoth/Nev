
import std/[strformat, options]
import logging, util
export logging, strformat

# var logger* = newConsoleLogger()

type
  CustomLogger* = ref object of Logger
    consoleLogger: Option[ConsoleLogger]
    fileLogger: Option[FileLogger]

proc newCustomLogger*(levelThreshold = lvlAll, fmtStr = defaultFmtStr): CustomLogger =
  new result
  result.fmtStr = fmtStr
  result.levelThreshold = levelThreshold

proc enableFileLogger*(self: CustomLogger) =
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
    logger.FileLogger.file.flushFile()
  elif logger of CustomLogger and logger.CustomLogger.fileLogger.getSome(l):
    l.flush()

template debug*(x: varargs[typed, `$`]) =
  logger.log(lvlDebug, x.join "")

template debugf*(x: static string) =
  logger.log(lvlDebug, fmt x)