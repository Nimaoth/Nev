## Runs documentation scenarios with the SDL platform and saves screenshots/recordings.
##
## Scenarios live in `screenshots/scenarios`, either as `<name>.json` or as
## `<name>/scenario.json` (the folder may contain extra files and subdirectories,
## which are copied into a fresh workspace for every run). Output goes to
## `../NevScreenshots/`, with all screenshots and GIFs in that single folder.
## Only files named by the scenario are replaced; unrelated outputs are preserved.
##
## Every scenario launches a new `nev -g --skip-user` instance with
## NEV_SDL_DEBUG_DIR pointing to a control dir, and drives it by writing commands
## to `<control>/commands` and watching `<control>/frame.txt`.
##
## Build: nim c -d:release --undef:useDynlib -o:tools/screenshot_scenarios.exe tools/screenshot_scenarios.nim
##
## Scenario file (JSON with comments and trailing commas):
##   {
##     "description": "Two files side by side",
##     "skip": "Feature unavailable",    // optional: skip this scenario with a reason
##     "size": "1280x720",               // window size, or [1280, 720]
##     "workspace": "../../..",          // optional: run in this dir (relative to the
##                                       //   scenario file) instead of a copy of the scenario folder
##     "file": "a.nim",                  // optional: file to open (nev command line argument)
##     "session": "x.nev-session",       // optional: session to load
##     "settings": {"ui.font-size": 16}, // optional: -p:key=value (text.cursor-blink defaults to false)
##     "args": [],                       // optional: extra command line arguments
##     "user-config": false,             // optional: load user config (default: --skip-user)
##     "setup": [["git", "init"]],        // optional: checked external commands in the copied workspace
##     "startup-idle": 1000,             // ms without rendering before the first step
##     "steps": [
##       "focus-view-left",                             // command line
##       ["open", "b.nim"],                             // command + JSON args
##       // split: pairs the active view with the previously shown one (needs two open files)
##       ["wrap-layout", {"kind": "horizontal", "temporary": true, "max-children": 2}],
##       {"command": "open", "args": ["c.nim"]},
##       {"keys": "jjjw<C-d>", "interval": 100},        // input-keys, optionally one key at a time
##       {"wait": 500},                                 // ms
##       {"wait-idle": 300, "timeout": 5000},           // until nothing rendered for 300ms
##       {"screenshot": "overview"},                    // <out>/overview.png
##       {"start-recording": "typing", "seconds": 5, "max-frames": 0}, // <out>/typing.gif with --gif
##       {"stop-recording": true},                      // also done automatically at the end
##     ]
##   }
##
## Failed commands and ERROR lines in nev's log (`<work>/<name>.log`) are reported as warnings.

when defined(useDynlib):
  {.error: "Build screenshot_scenarios with --undef:useDynlib; it must not import Nev's dynamic runtime.".}

import std/[os, osproc, strutils, strformat, streams, strtabs, parseopt, algorithm,
  sequtils, monotimes, times]
from std/unicode import runeLenAt
import ../src/misc/jsonex

const repoRoot = currentSourcePath().parentDir.parentDir

type
  ScenarioError = object of CatchableError
  ScenarioOutcome = enum scenarioSucceeded, scenarioFailed, scenarioSkipped

  Scenario = object
    name: string
    file: string          ## scenario json
    folder: string        ## scenario folder, "" for single file scenarios
    json: JsonNodeEx

  Runner = object
    nevExe: string
    outRoot: string
    workRoot: string
    gif: bool
    verbose: bool

  Run = object
    scenario: Scenario
    outDir: string
    controlDir: string
    process: Process
    commandsLogLen: int
    logFile: string
    logLen: int
    recording: string     ## name of the active recording, "" if none
    warnings: int
    verbose: bool

proc fail(msg: string) {.noreturn.} =
  raise newException(ScenarioError, msg)

proc ms(d: Duration): int = d.inMilliseconds.int

proc elapsedMs(start: MonoTime): int = (getMonoTime() - start).ms

proc warn(run: var Run, msg: string) =
  inc run.warnings
  echo &"  warning: {msg}"

# --- Scenario discovery -------------------------------------------------------

proc scenariosDir(): string = repoRoot / "screenshots" / "scenarios"

proc findScenarios(): seq[Scenario] =
  let dir = scenariosDir()
  if not dirExists(dir):
    return
  for kind, path in walkDir(dir):
    case kind
    of pcFile:
      if path.endsWith(".json"):
        result.add Scenario(name: path.splitFile.name, file: path)
    of pcDir:
      if fileExists(path / "scenario.json"):
        result.add Scenario(name: path.extractFilename, file: path / "scenario.json", folder: path)
    else:
      discard
  result.sort(proc(a, b: Scenario): int = cmp(a.name, b.name))

proc load(scenario: var Scenario) =
  try:
    scenario.json = parseFile(scenario.file)
  except CatchableError as e:
    fail &"Failed to parse '{scenario.file}': {e.msg}"
  if scenario.json.kind != JsonexNodeKind.JObject:
    fail &"'{scenario.file}': expected an object"

proc get(node: JsonNodeEx, key: string): JsonNodeEx =
  if node != nil and node.kind == JsonexNodeKind.JObject and node.hasKey(key):
    node[key]
  else:
    nil

proc getInt(node: JsonNodeEx, key: string, default: int): int =
  let n = node.get(key)
  if n == nil: default
  elif n.kind == JsonexNodeKind.JInt: n.num.int
  elif n.kind == JsonexNodeKind.JFloat: n.fnum.int
  else: fail &"'{key}' must be a number"

proc getFloat(node: JsonNodeEx, key: string, default: float): float =
  let n = node.get(key)
  if n == nil: default
  elif n.kind == JsonexNodeKind.JInt: n.num.float
  elif n.kind == JsonexNodeKind.JFloat: n.fnum
  else: fail &"'{key}' must be a number"

proc getString(node: JsonNodeEx, key: string, default = ""): string =
  let n = node.get(key)
  if n == nil: default
  elif n.kind == JsonexNodeKind.JString: n.str
  else: fail &"'{key}' must be a string"

proc toArg(node: JsonNodeEx): string =
  ## Command arguments are JSON values.
  $node

proc quoted(s: string): string = $(%%s)

proc mediaName(step: JsonNodeEx, key: string): string =
  result = step.getString(key)
  if result.len == 0 or result in [".", ".."] or
      result.anyIt(it notin {'a'..'z', 'A'..'Z', '0'..'9', '-', '_', '.'}):
    fail &"'{key}' must be a filename containing only letters, digits, '-', '_' and '.'"

# --- Process control ----------------------------------------------------------

proc drainOutput(args: tuple[stream: Stream, path: string]) {.thread.} =
  {.cast(gcsafe).}:
    try:
      let f = open(args.path, fmWrite)
      defer: f.close()
      var line = ""
      while args.stream.readLine(line):
        f.writeLine(line)
        f.flushFile()
    except CatchableError, IOError:
      discard

proc reportLogErrors(run: var Run) =
  ## Turns ERROR lines nev logged since the last call into warnings.
  let content = try: readFile(run.logFile) except CatchableError: return
  let lastNewline = content.rfind('\n')
  if lastNewline < run.logLen:
    return
  for line in content[run.logLen..lastNewline].splitLines:
    if " ERROR [" in line:
      run.warn "nev: " & line.strip
  run.logLen = lastNewline + 1

proc frameCount(run: Run): int =
  ## frame.txt is written non-atomically, so a read may see an empty file.
  try:
    readFile(run.controlDir / "frame.txt").strip.parseInt
  except CatchableError:
    -1

proc checkAlive(run: Run) =
  if not run.process.running:
    fail &"nev exited with code {run.process.peekExitCode}"

proc waitForFrame(run: var Run, after: int, timeoutMs: int): bool =
  let start = getMonoTime()
  while start.elapsedMs < timeoutMs:
    run.checkAlive()
    if run.frameCount() > after:
      return true
    sleep(10)
  false

proc waitIdle(run: var Run, idleMs: int, timeoutMs: int) =
  ## Waits until no frame was rendered for `idleMs`.
  let start = getMonoTime()
  var last = run.frameCount()
  var lastChange = getMonoTime()
  while start.elapsedMs < timeoutMs:
    run.checkAlive()
    sleep(10)
    let frame = run.frameCount()
    if frame == -1:
      continue
    if frame != last:
      last = frame
      lastChange = getMonoTime()
    elif lastChange.elapsedMs >= idleMs:
      return
  run.warn &"not idle for {idleMs}ms within {timeoutMs}ms"

proc readNewCommandResults(run: var Run): string =
  try:
    let content = readFile(run.controlDir / "commands.log")
    result = content[min(run.commandsLogLen, content.len)..^1]
    run.commandsLogLen = content.len
  except CatchableError:
    discard

proc execute(run: var Run, commands: seq[string], timeoutMs = 5000): string =
  ## Runs the commands in nev (all in the same frame) and returns their results.
  let path = run.controlDir / "commands"
  let tempPath = path & ".tmp"
  writeFile(tempPath, commands.join("\n"))
  moveFile(tempPath, path)
  let start = getMonoTime()
  while fileExists(path):
    run.checkAlive()
    if start.elapsedMs > timeoutMs:
      fail &"nev didn't pick up commands within {timeoutMs}ms: {commands}"
    sleep(5)
  # commands.log is written right after the commands file is removed.
  while start.elapsedMs < timeoutMs:
    result = run.readNewCommandResults()
    if result.len > 0:
      break
    sleep(5)
  if run.verbose:
    for line in result.strip.splitLines:
      echo "    ", line
  if "Failed to execute command" in result:
    run.warn result.strip

proc execute(run: var Run, command: string): string =
  run.execute(@[command])

proc commandResult(output: string): string =
  ## Extracts the (JSON string) result of the last command from commands.log output.
  let i = output.rfind("-> ")
  if i == -1:
    return ""
  let value = output[i + 3..^1].strip
  try:
    let node = parseJsonex(value)
    if node.kind == JsonexNodeKind.JString: node.str else: value
  except CatchableError:
    value

proc waitForFile(run: var Run, path: string, timeoutMs = 10000) =
  let start = getMonoTime()
  while not fileExists(path):
    run.checkAlive()
    if start.elapsedMs > timeoutMs:
      fail &"'{path}' was not written within {timeoutMs}ms"
    sleep(10)

# --- Recordings ---------------------------------------------------------------

proc writeConcatFile(dir: string): string =
  ## Writes frames.ffconcat (frame timings for ffmpeg's concat demuxer) and returns its path.
  let lines = readFile(dir / "index.txt").splitLines
  var total = 0.0
  var frames: seq[(float, string)]
  for line in lines:
    if line.startsWith("# ") and "frames," in line:
      let parts = line.split(", ")
      try:
        total = parts[^1].strip(chars = {'s', ' '}).parseFloat
      except ValueError:
        discard
    elif line.len > 0 and not line.startsWith("#"):
      let parts = line.splitWhitespace
      if parts.len == 3:
        frames.add (parts[1].parseFloat, parts[2])
  if frames.len == 0:
    return ""
  var content = "ffconcat version 1.0\n"
  for i, (time, file) in frames:
    let next = if i < frames.high: frames[i + 1][0] else: max(total, time + 0.5)
    content.add &"file '{file}'\nduration {max(next - time, 0.001):.4f}\n"
  # The concat demuxer ignores the duration of the last entry unless it is repeated.
  content.add &"file '{frames[^1][1]}'\n"
  result = dir / "frames.ffconcat"
  writeFile(result, content)

proc convertToGif(run: var Run, dir, output: string, concatFile: string) =
  let ffmpeg = findExe("ffmpeg")
  if ffmpeg.len == 0:
    fail "--gif: ffmpeg not found in PATH (recording frames retained)"
  let temporaryOutput = output.changeFileExt("tmp.gif")
  let filter = "fps=30,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=none"
  let (outp, code) = execCmdEx(quoteShellCommand([ffmpeg, "-y", "-loglevel", "error",
    "-f", "concat", "-safe", "0", "-i", concatFile, "-vf", filter, temporaryOutput]))
  if code != 0:
    removeFile(temporaryOutput)
    fail &"ffmpeg failed ({code}), recording frames retained: {outp}"
  if not fileExists(temporaryOutput) or getFileSize(temporaryOutput) == 0:
    fail "ffmpeg produced no GIF (recording frames retained)"
  moveFile(temporaryOutput, output)
  for frame in walkFiles(dir / "frame-*.png"):
    removeFile(frame)
  removeFile(concatFile)
  echo &"  gif: {output}"

proc clearRawRecording(run: Run, name: string) =
  for frame in walkFiles(run.outDir / (name & "-frame-*.png")):
    removeFile(frame)
  removeFile(run.outDir / (name & ".index.txt"))
  removeFile(run.outDir / (name & ".ffconcat"))

proc stopRecording(run: var Run, runner: Runner) =
  if run.recording.len == 0:
    return
  let name = run.recording
  run.recording = ""
  discard run.execute("sdl.stop-recording")
  let dir = run.controlDir / name
  run.waitForFile(dir / "index.txt")
  # index.txt is written when the recording stops, frames may still be encoding.
  for line in readFile(dir / "index.txt").splitLines:
    if line.len > 0 and not line.startsWith("#"):
      let parts = line.splitWhitespace
      if parts.len == 3:
        run.waitForFile(dir / parts[2], 30000)
  let header = readFile(dir / "index.txt").splitLines[0].strip(chars = {'#', ' '})
  echo &"  recording '{name}': {header}"
  let concatFile = writeConcatFile(dir)
  if runner.gif and concatFile.len > 0:
    run.convertToGif(dir, run.outDir / name & ".gif", concatFile)
    run.clearRawRecording(name)
  elif not runner.gif:
    run.clearRawRecording(name)
    for frame in walkFiles(dir / "frame-*.png"):
      moveFile(frame, run.outDir / (name & "-" & frame.extractFilename))
    let index = readFile(dir / "index.txt").replace(" frame-", " " & name & "-frame-")
    writeFile(run.outDir / (name & ".index.txt"), index)
    if concatFile.len > 0:
      let concat = readFile(concatFile).replace("file 'frame-", "file '" & name & "-frame-")
      writeFile(run.outDir / (name & ".ffconcat"), concat)

# --- Steps --------------------------------------------------------------------

proc splitKeys(keys: string): seq[string] =
  ## Splits input-keys notation into single keys, e.g. "ab<C-d>" -> a, b, <C-d>.
  var i = 0
  while i < keys.len:
    if keys[i] == '<':
      let close = keys.find('>', i + 1)
      if close > i + 1:
        result.add keys[i..close]
        i = close + 1
        continue
    let len = keys.runeLenAt(i)
    result.add keys[i ..< i + len]
    i += len

proc commandLine(name: string, args: openArray[JsonNodeEx]): string =
  result = name
  for arg in args:
    result.add " " & arg.toArg

proc runStep(run: var Run, runner: Runner, step: JsonNodeEx) =
  case step.kind
  of JsonexNodeKind.JString:
    discard run.execute(step.str)

  of JsonexNodeKind.JArray:
    if step.elems.len == 0 or step.elems[0].kind != JsonexNodeKind.JString:
      fail &"Command step must start with the command name: {step}"
    discard run.execute(commandLine(step.elems[0].str, step.elems[1..^1]))

  of JsonexNodeKind.JObject:
    if step.hasKey("command"):
      let args = step.get("args")
      let argList = if args == nil: @[] elif args.kind == JsonexNodeKind.JArray: args.elems else: @[args]
      discard run.execute(commandLine(step.getString("command"), argList))

    elif step.hasKey("keys"):
      let keys = step.getString("keys")
      let interval = step.getInt("interval", 0)
      if interval <= 0:
        discard run.execute("input-keys " & keys.quoted)
      else:
        for key in keys.splitKeys:
          let start = getMonoTime()
          discard run.execute("input-keys " & key.quoted)
          sleep(max(interval - start.elapsedMs, 0))

    elif step.hasKey("wait"):
      let ms = step.getInt("wait", 0)
      let start = getMonoTime()
      while start.elapsedMs < ms:
        run.checkAlive()
        sleep(min(10, ms))

    elif step.hasKey("wait-idle"):
      run.waitIdle(step.getInt("wait-idle", 300), step.getInt("timeout", 5000))

    elif step.hasKey("screenshot"):
      let name = step.mediaName("screenshot")
      let path = run.outDir / name & ".png"
      removeFile(path)
      discard run.execute("sdl.screenshot " & path.quoted)
      run.waitForFile(path)
      echo &"  screenshot: {path}"

    elif step.hasKey("start-recording"):
      run.stopRecording(runner)
      let name = step.mediaName("start-recording")
      let dir = run.controlDir / name
      removeDir(dir)
      let res = run.execute(&"sdl.start-recording {dir.quoted} {step.getFloat(\"seconds\", 0)} {step.getInt(\"max-frames\", 0)}")
      if res.commandResult.len == 0:
        fail &"Failed to start recording '{name}': {res.strip}"
      run.recording = name

    elif step.hasKey("stop-recording"):
      run.stopRecording(runner)

    else:
      fail &"Unknown step: {step}"

  else:
    fail &"Invalid step: {step}"

# --- Scenario execution -------------------------------------------------------

proc parseSize(node: JsonNodeEx): (int, int) =
  if node == nil:
    return (1280, 720)
  if node.kind == JsonexNodeKind.JArray and node.elems.len == 2:
    return (node.elems[0].getInt, node.elems[1].getInt)
  if node.kind == JsonexNodeKind.JString:
    let parts = node.str.toLowerAscii.split('x')
    if parts.len == 2:
      try:
        return (parts[0].strip.parseInt, parts[1].strip.parseInt)
      except ValueError:
        discard
  fail &"Invalid size {node}, expected \"<w>x<h>\" or [w, h]"

proc prepareWorkspace(runner: Runner, scenario: Scenario): string =
  let workspace = scenario.json.getString("workspace")
  if workspace.len > 0:
    result = (scenario.file.parentDir / workspace).normalizedPath.absolutePath
    if not dirExists(result):
      fail &"Workspace '{result}' doesn't exist"
    return
  # Fresh copy so steps which edit or save files don't modify the scenario.
  result = runner.workRoot / scenario.name
  removeDir(result)
  if scenario.folder.len > 0:
    copyDir(scenario.folder, result)
    removeFile(result / "scenario.json")
  else:
    createDir(result)

proc runScenario(runner: Runner, scenario: var Scenario): ScenarioOutcome =
  echo &"[{scenario.name}]"
  let start = getMonoTime()
  var run = Run(scenario: scenario, verbose: runner.verbose)
  var outputThread: Thread[tuple[stream: Stream, path: string]]
  var started = false
  try:
    scenario.load()
    run.scenario = scenario
    let json = scenario.json
    let skip = json.getString("skip")
    if skip.len > 0:
      echo &"  SKIPPED: {skip}"
      return scenarioSkipped
    let (width, height) = parseSize(json.get("size"))

    run.outDir = runner.outRoot
    createDir(run.outDir)
    run.controlDir = runner.workRoot / scenario.name & ".control"
    removeDir(run.controlDir)
    createDir(run.controlDir)
    let workspace = prepareWorkspace(runner, scenario)
    let setup = json.get("setup")
    if setup != nil:
      if json.getString("workspace").len > 0:
        fail "'setup' requires a copied scenario workspace"
      if setup.kind != JsonexNodeKind.JArray:
        fail "'setup' must be an array of command arrays"
      for command in setup:
        if command.kind != JsonexNodeKind.JArray or command.elems.len == 0:
          fail "'setup' commands must be nonempty arrays of strings"
        var argv: seq[string]
        for arg in command:
          if arg.kind != JsonexNodeKind.JString:
            fail "'setup' arguments must be strings"
          argv.add arg.str
        let (output, code) = execCmdEx(quoteShellCommand(argv), workingDir = workspace)
        if code != 0:
          fail &"Setup command {argv} failed ({code}): {output}"

    var args = @["-g", "--no-attach"]
    if not json.get("user-config").getBool(false):
      args.add "--skip-user"
    let session = json.getString("session")
    if session.len > 0:
      args.add "-s:" & session
    let settings = json.get("settings")
    # Blinking keeps nev rendering (breaking idle detection) and makes screenshots random.
    if settings == nil or not settings.hasKey("text.cursor-blink"):
      args.add "-p:text.cursor-blink=false"
    if settings != nil:
      for key, value in settings.pairs:
        args.add &"-p:{key}={value.toArg}"
    if json.get("args") != nil:
      for arg in json.get("args"):
        args.add arg.getStr
    let file = json.getString("file")
    if file.len > 0:
      args.add file

    let env = newStringTable(modeCaseInsensitive)
    for key, value in envPairs():
      env[key] = value
    env["NEV_SDL_DEBUG_DIR"] = run.controlDir
    env["NEV_SDL_DEBUG_FRAMES"] = "0"
    env["NEV_SDL_IGNORE_MOUSE"] = "1"
    env["NEV_SDL_WINDOW_SIZE"] = &"{width}x{height}"

    let logFile = runner.workRoot / scenario.name & ".log"
    run.logFile = logFile
    if runner.verbose:
      echo &"  nev {args.join(\" \")} (in {workspace}, log: {logFile})"
    run.process = startProcess(runner.nevExe, workingDir = workspace, args = args, env = env,
      options = {poStdErrToStdOut})
    started = true
    createThread(outputThread, drainOutput, (run.process.outputStream, logFile))

    if not run.waitForFrame(0, json.getInt("startup-timeout", 30000)):
      fail "No frame rendered during startup"
    # Let async startup work (configs, treesitter, git, LSPs) settle.
    run.waitIdle(json.getInt("startup-idle", 1000), json.getInt("startup-timeout", 30000))
    run.reportLogErrors()

    let steps = json.get("steps")
    if steps != nil:
      if steps.kind != JsonexNodeKind.JArray:
        fail "'steps' must be an array"
      for i, step in steps.elems:
        if runner.verbose:
          echo &"  step {i}: {step}"
        try:
          run.runStep(runner, step)
        except ScenarioError as e:
          fail &"step {i} ({step}): {e.msg}"
        run.reportLogErrors()
    run.stopRecording(runner)
    sleep(50)
    run.reportLogErrors()
    echo &"  done in {start.elapsedMs.float / 1000:.1f}s, {run.warnings} warnings -> {run.outDir}"
    result = scenarioSucceeded
  except CatchableError as e:
    echo &"  FAILED: {e.msg}"
    result = scenarioFailed
  finally:
    if started:
      if run.process.running:
        run.process.terminate()
      discard run.process.waitForExit(5000)
      joinThread(outputThread)
      run.process.close()

# --- Main ---------------------------------------------------------------------

const usage = """
Usage: screenshot_scenarios [options] [scenario...]

Runs the scenarios in screenshots/scenarios (all if none are given) and writes
screenshots/recordings directly to <out>/ (no per-scenario output folders).

Options:
  --list          List scenarios and exit
  --out:DIR       Output directory (default: ../NevScreenshots)
  --nev:PATH      nev executable (default: nev.exe in the repository root)
  --work:DIR      Directory for workspaces, logs and control files
                  (default: <temp>/nev-scenarios)
  --gif           Convert recordings to <name>.gif, then delete PNG frames
                  (requires ffmpeg in PATH; frames retained on conversion failure)
  -v, --verbose   Print commands, results and steps
"""

proc main(): int =
  var runner = Runner(
    nevExe: repoRoot / "nev".addFileExt(ExeExt),
    outRoot: (repoRoot / ".." / "NevScreenshots").normalizedPath,
    workRoot: getTempDir() / "nev-scenarios",
  )
  var names: seq[string]
  var list = false
  for kind, key, val in getopt():
    case kind
    of cmdArgument:
      names.add key
    of cmdLongOption, cmdShortOption:
      case key
      of "list", "l": list = true
      of "out", "o": runner.outRoot = val.absolutePath
      of "nev": runner.nevExe = val.absolutePath
      of "work": runner.workRoot = val.absolutePath
      of "gif": runner.gif = true
      of "verbose", "v": runner.verbose = true
      of "help", "h":
        echo usage
        return 0
      else:
        echo &"Unknown option '{key}'\n{usage}"
        return 1
    of cmdEnd:
      discard

  var all = findScenarios()
  if list:
    for scenario in all.mitems:
      var description = ""
      try:
        scenario.load()
        description = scenario.json.getString("description")
        let skip = scenario.json.getString("skip")
        if skip.len > 0:
          description.add &" [skipped: {skip}]"
      except CatchableError as e:
        description = "(invalid: " & e.msg & ")"
      echo &"{scenario.name:<30} {description}"
    return 0

  var selected: seq[Scenario]
  if names.len == 0:
    selected = all
  for name in names:
    let matches = all.filterIt(it.name == name)
    if matches.len == 0:
      echo &"Unknown scenario '{name}', available: {all.mapIt(it.name).join(\", \")}"
      return 1
    selected.add matches[0]

  if selected.len == 0:
    echo &"No scenarios found in {scenariosDir()}"
    return 1
  if not fileExists(runner.nevExe):
    echo &"nev not found at '{runner.nevExe}'"
    return 1
  createDir(runner.outRoot)
  createDir(runner.workRoot)

  var failed: seq[string]
  var skipped = 0
  for scenario in selected.mitems:
    case runner.runScenario(scenario)
    of scenarioFailed:
      failed.add scenario.name
    of scenarioSkipped:
      inc skipped
    of scenarioSucceeded:
      discard
  echo &"{selected.len - failed.len - skipped}/{selected.len - skipped} scenarios succeeded, {skipped} skipped"
  if failed.len > 0:
    echo &"Failed: {failed.join(\", \")}"
    return 1
  return 0

when isMainModule:
  quit(main())
