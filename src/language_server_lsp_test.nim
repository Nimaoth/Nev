import asyncdispatch, strutils, strformat, threadpool
import lsp_client

var client = LSPClient()
waitFor client.connect("zls")
# waitFor client.connect("C:/Users/nimao/.vscode/extensions/rust-lang.rust-analyzer-0.3.1317-win32-x64/server/rust-analyzer.exe")
client.run()

let testFile = "D:/dev/Nim/Absytree/temp/test.zig"
waitFor client.notifyOpenedTextDocument(testFile, readFile(testFile))

# Read commands from stdin and send requests based on that
var messageFlowVar = spawn stdin.readLine()
while true:
  poll()

  if messageFlowVar.isReady:
    defer:
      messageFlowVar = spawn stdin.readLine()

    let line = ^messageFlowVar
    let parts = line.split " "
    if parts.len == 0:
      continue

    case parts[0]:
    of "c":
      if parts.len != 3:
        continue
      let line = parts[1].parseInt
      let column = parts[2].parseInt
      client.getCompletions((testFile, line, column)).addCallback proc (f: Future[Response[CompletionList]]) =
        let response = f.read
        if response.isError:
          echo fmt"Failed to get completions: {response.error}"
          return

        let completionList = response.result
        echo "isIncomplete: ", completionList.isIncomplete, ", len: ", completionList.items.len

    of "q":
      break

echo "[main] Quitting..."
client.close()
quit(0)