import std/[tables, macros, genasts, macrocache, strutils, compilesettings]
import misc/[util]

proc normalizeSourcePath*(path: string): string =
  var stripLeading = false
  if path.startsWith("/") and path.len >= 3 and path[2] == ':':
    # Windows path: /C:/...
    stripLeading = true
  result = path.replace('\\', '/').strip(leading=stripLeading, chars={'/'})
  if result.len >= 2 and result[1] == ':':
    result[0] = result[0].toUpperAscii

const staticSourceFiles* = CacheSeq"SourceFiles"
const projPath = querySetting(SingleValueSetting.projectPath).normalizeSourcePath & "/"

var sourceFiles = initTable[string, string]()

template currentSourceLocation*(depth: static int = -1): tuple[filename: string, line: int, column: int] =
  block:
    if instantiationInfo(depth, true).filename.normalizeSourcePath.startsWith(projPath):
      (instantiationInfo(depth, true).filename[projPath.len..^1].normalizeSourcePath, instantiationInfo(depth, true).line, instantiationInfo(depth, true).column)
    else:
      (instantiationInfo(depth, true).filename.normalizeSourcePath, instantiationInfo(depth, true).line, instantiationInfo(depth, true).column)

macro embedSourceImpl(path: static string): untyped =
  staticSourceFiles.add newLit path

macro generateEmbeddedSourceMap*() =
  when not defined(nimscript):
    result = genAst():
      sourceFiles = toTable([])
    for path in staticSourceFiles:
      result[1][1].add(nnkTupleConstr.newTree(path, nnkStaticExpr.newTree(nnkCall.newTree(ident"staticRead", path))))
  else:
    return nnkStmtList.newTree()

template embedSource*(): untyped =
  ## Embed the source code of the file where this is called in the program
  ## Content can be retrieved with `getEmbeddedSourceFile`
  when not defined(nimscript):
    embedSourceImpl(instantiationInfo(-1, true).filename.normalizeSourcePath)

iterator embeddedSourceFiles*(): tuple[path, content: string] =
  ## Iterate all source files embedded with `embedSource`
  for entry in sourceFiles.pairs:
    yield entry

proc getEmbeddedSourceFile*(path: string): string =
  ## Returns the file content of the source file. File has to be embedded with `embedSource`.
  {.gcsafe.}:
    if sourceFiles.contains(path):
      return sourceFiles[path]
    return ""
