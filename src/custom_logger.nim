
import std/[strformat]
import logging
export logging, strformat

# var logger* = newConsoleLogger()

var file = open("messages.log", fmWrite)
var logger* = newFileLogger(file, flushThreshold=lvlAll)

proc flush*(logger: Logger) =
  if logger of FileLogger:
    logger.FileLogger.file.flushFile()

template debug*(x: varargs[typed, `$`]) =
  logger.log(lvlDebug, x.join "")

template debugf*(x: static string) =
  logger.log(lvlDebug, fmt x)