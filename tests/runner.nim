import std/[parseopt, os, strutils]
import chronos
import misc/async_process

var fileToRun = ""
block: ## Parse command line options
  var optParser = initOptParser("")

  for kind, key, val in optParser.getopt():
    case kind
    of cmdArgument:
      fileToRun = key.absolutePath
    else:
      echo "invalid args"
      quit(1)

let (dir, name, ext) = fileToRun.splitFile
var (output, err) = waitFor runProcessAsyncOutput(fileToRun, @[])

if output.contains("\r\n"):
  echo "Replacing \\r\\n with \\n"
  output = output.replace("\r\n", "\n")

if output.startsWith("\xEF\xBB\xBF"):
  echo "Removing utf8 bom"
  output = output[3..^1]

if err.len > 0:
  echo "========== error =========="
  echo err
  echo "=========="

let resultPath = dir & "/" & name & ".txt"
echo "Write result of ", fileToRun, " to ", resultPath
writeFile(resultPath, output)
