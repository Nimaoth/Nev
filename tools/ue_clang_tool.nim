import std/[os, strutils, strformat, tables, sequtils, options, json, jsonutils]

type UnrealVersion = enum V4_27, V5_3
let unrealVersion = V5_3
let platform = "Win64"
let unrealRootPath = "/mnt/c/Program Files/Epic Games/UE_5.3"
let enginePath = unrealRootPath / "Engine"
let cppVersion = "-std=c++17"
let buildType = "UE_BUILD_DEVELOPMENT"

type ModuleInfo = object
  path: string
  name: string
  apiDefine: string
  private: Option[string]
  public: Option[string]
  classes: Option[string]
  sources: seq[string]
  headers: seq[string]

proc containsModule(path: string): bool =
 dirExists(path / "Private") or dirExists(path / "Public") or dirExists(path / "Classes")

proc collectSourceFiles(module: var ModuleInfo, dir: string) =
  for (kind, path) in walkDir(dir, relative=false):
    case kind
    of pcFile:
      let ext = path.splitFile.ext
      if ext == ".cpp" or ext == ".c":
        module.sources.add path
      elif ext == ".h" or ext == ".hpp":
        module.headers.add path
    of pcDir:
      module.collectSourceFiles(path)
    else:
      discard

proc getModuleName(dir: string): string =
  for (kind, path) in walkDir(dir, relative=false):
    case kind
    of pcFile:
      if path.toLowerAscii.endsWith(".build.cs"):
        let fileName = path.extractFilename
        return fileName[0..^10]

    else:
      discard

  return dir.extractFilename

proc getModuleInfo(path: string): ModuleInfo =
  result.path = path
  result.name = path.getModuleName
  result.apiDefine = result.name.toUpperAscii & "_API"
  if dirExists(path / "Private"):
    result.private = some(path / "Private")
    result.collectSourceFiles(result.private.get)
  if dirExists(path / "Public"):
    result.public = some(path / "Public")
    result.collectSourceFiles(result.public.get)
  if dirExists(path / "Classes"):
    result.classes = some(path / "Classes")
    result.collectSourceFiles(result.classes.get)

proc collectSourceModules(projectPath: string, modules: var seq[ModuleInfo], rec: int = 0) =
  let indent = "  ".repeat(rec)
  # echo indent, "Collecting modules for ", projectPath
  for (kind, path) in walkDir(projectPath, relative=false):
    case kind
    of pcFile:
      discard
    of pcDir:
      if path.containsModule:
        # echo indent, "  > Found module ", path
        # echo path
        modules.add path.getModuleInfo()
      else:
        collectSourceModules(path, modules, rec + 1)
    else:
      discard

proc getUhtRootPath(projectPath: string): string =
  case unrealVersion
  of V5_3: projectPath / "Intermediate/Build" / platform / "UnrealEditor/Inc"
  of V4_27: projectPath / "Intermediate/Build" / platform / "UE4Editor/Inc"

proc collectUHTPaths(projectPath: string, uhtPaths: var seq[string]) =
  for (kind, path) in walkDir(projectPath, relative=false):
    case kind
    of pcFile:
      discard
    of pcDir:
      let uhtPath = case unrealVersion
        of V5_3: path / "UHT"
        of V4_27: path
      if dirExists(uhtPath):
        uhtPaths.add uhtPath
      else:
        collectUHTPaths(path, uhtPaths)
    else:
      discard

proc toNativePath(path: string): string =
  if path.startsWith "/mnt/":
    let drive = path[5]
    return drive.toUpperAscii & ":" & path[6..^1]
  else:
    return path

let defaultDefines = @[
  "__cpp_if_constexpr",
  "__cpp_fold_expressions",

  buildType,

  "WITH_EDITOR=1",
  "WITH_ENGINE=0",
  "WITH_UNREAL_DEVELOPER_TOOLS=1",
  "WITH_UNREAL_TARGET_DEVELOPER_TOOLS=1",
  "WITH_PLUGIN_SUPPORT=1",
  "WITH_HOT_RELOAD=1",
  "WITH_LIVE_CODING=1",
  "WITH_SERVER_CODE",
  "IS_MONOLITHIC=0",
  "IS_PROGRAM=0",

  "OVERRIDE_PLATFORM_HEADER_NAME=Windows",
  "PLATFORM_WINDOWS",

  "_UNICODE",
  "UNICODE",
  "WINVER=0x0A00",
]

let ue4Defines = @[
  "ENABLE_LOW_LEVEL_MEM_TRACKER=1",
  "UNIQUENETID_ESPMODE=ESPMode::Fast",
  "PHYSICS_INTERFACE_PHYSX",
  "WITH_PHYSX",
  "WITH_PHYSX_VEHICLES",

  # Required by PxPreprocessor.h - Either that or NDEBUG
  "_DEBUG",
]

let ue5Defines: seq[string] = @[]

let defaultUndefines = @[
  # undefine __OBJC__ (for objective-c), idk why this is defined by default
  "__OBJC__"
]

proc createCompileArguments(modules: seq[ModuleInfo], uhtPaths: seq[string]): seq[string] =
  result.add defaultDefines.mapIt("-D" & it)

  case unrealVersion
  of V4_27: result.add ue4Defines.mapIt("-D" & it)
  of V5_3: result.add ue5Defines.mapIt("-D" & it)
  result.add defaultUndefines.mapIt("-U" & it)

  for module in modules:
    result.add "-D" & module.apiDefine & "="

  for module in modules:
    if module.classes.isSome:
      result.add "-I" & module.classes.get.toNativePath
    if module.public.isSome:
      result.add "-I" & module.public.get.toNativePath

  result.add uhtPaths.mapIt("-I" & it.toNativePath)

proc createCompileCommands(outputDir: string) =
  var modules: seq[ModuleInfo] = @[]
  var uhtPaths: seq[string] = @[]
  collectSourceModules(enginePath / "Source" / "Runtime", modules)
  collectSourceModules(enginePath / "Source" / "Developer", modules)
  collectSourceModules(enginePath / "Source" / "Editor", modules)
  collectUHTPaths(enginePath.getUhtRootPath, uhtPaths)

  let argumentsFile = "compile_arguments.txt"
  writeFile(argumentsFile, createCompileArguments(modules, uhtPaths).join("\n"))

  var arr = newJArray()
  for module in modules:
    if arr.len > 100:
      break
    for file in module.sources:
      var arguments = @[
        "clang++",
        cppVersion,
        "-I" & (enginePath / "Shaders/Shared").toNativePath
      ] & createCompileArguments(modules, uhtPaths)
      let directory = module.path.toNativePath
      arr.add %*{
        "file": file.toNativePath,
        "arguments": %* arguments,
        "directory": directory,
      }

  var result = arr.pretty
  writeFile("compile_commands.json", result)

  for path in uhtPaths:
    echo path

createCompileCommands(enginePath)