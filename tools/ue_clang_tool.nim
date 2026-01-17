import std/[os, strutils, strformat, tables, sequtils, options, json, jsonutils]
# import "../src/misc/regex"
import "../src/misc"/[regex, timer]

type UnrealVersion = enum V4_27, V5_3
let unrealVersion = V5_3
let platform = "Win64"
let unrealRootPath = "/mnt/c/Program Files/Epic Games/UE_5.3"
let enginePath = unrealRootPath / "Engine"
let cppVersion = "-std=c++17"
let buildType = "UE_BUILD_DEVELOPMENT"

let ignoreFile = readFile(".clang-ignore")
echo "ignore: \n", ignoreFile.indent(2)
let ignore = parseGlobs(ignoreFile)

proc shouldIgnore(path: string): bool =
  let path = path.replace("\\", "/")
  if ignore.excludePath(path) or ignore.excludePath(path.extractFilename):
    if ignore.includePath(path) or ignore.includePath(path.extractFilename):
      return false

    return true
  return false

type ModuleInfo2 = object
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
  if shouldIgnore(dir):
    echo "Ignoring source dir ", dir
    return

  for (kind, path) in walkDir(dir, relative=false):

    case kind
    of pcFile:
      if shouldIgnore(path):
        # echo "Ignoring source file ", path
        continue
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
  # if shouldIgnore(projectPath):
  #   echo "Ignoring module ", projectPath
  #   return

  # echo indent, "Collecting modules for ", projectPath
  for (kind, path) in walkDir(projectPath, relative=false):
    case kind
    of pcFile:
      discard
    of pcDir:
      # if shouldIgnore(path):
      #   echo "Ignoring ", path
      #   continue
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
  "WITH_ENGINE=1",
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
  "WITH_RECAST",
  "SOURCE_CONTROL_WITH_SLATE",
  "USE_STATS_WITHOUT_ENGINE=1",
  "UE_APP_NAME=\"UE4Editor\"",
  "UBT_MODULE_MANIFEST_DEBUGGAME=1",
  "LOAD_PLUGINS_FOR_TARGET_PLATFORMS=\"todo\"",
  "UBT_MODULE_MANIFEST=\"todo\"",
  "UE_EDITOR=1",

  # Required by PxPreprocessor.h - Either that or NDEBUG
  "_DEBUG",

  "INTEL_ISPC=0",
  "READ_TARGET_ENABLED_PLUGINS_FROM_RECEIPT=1",
  "PLATFORM_COMPILER_OPTIMIZATION_PG=0",
  "WITH_FREETYPE=0",
  "WITH_HARFBUZZ=0",
]

let ue4Includes = @[
  "D:/BostonEngine/Engine/Source/ThirdParty/PhysX3/PxShared/include",
  "D:/BostonEngine/Engine/Source/ThirdParty/PhysX3/PxShared/include/foundation",
  "D:/BostonEngine/Engine/Source/ThirdParty/PhysX3/PxShared/include/pvd",
  "D:/BostonEngine/Engine/Source/ThirdParty/PhysX3/PhysX_3.4/Include",
  "D:/BostonEngine/Engine/Source/ThirdParty/PhysX3/PhysX_3.4/Include/common",
  "D:/BostonEngine/Engine/Source/ThirdParty/PhysX3/PhysX_3.4/Include/extensions",
  "D:/BostonEngine/Engine/Source/ThirdParty/PhysX3/PhysX_3.4/Include/geometry",

  # todo: only for Source/Runtime/Renderer
  "D:/BostonEngine/Engine/Source/Runtime/Renderer/Private/PostProcess",

  # todo: only for Source/Editor/Persona
  "D:/BostonEngine/Engine/Source/Editor/Persona/Private/AnimTimeline",

  # todo: only for Source/Editor/Sequencer
  "D:/BostonEngine/Engine/Source/Editor/Sequencer/Private/DisplayNodes",

  # todo: only for Source/Developer/AutomationDriver
  "D:/BostonEngine/Engine/Source/Developer/AutomationDriver/Private/MetaData",

  # todo: only for Source/Developer/AutomationDriver
  "D:/BostonEngine/Engine/Source/Editor/VREditor",
  "D:/BostonEngine/Engine/Source/Editor/VREditor/UI",
  "D:/BostonEngine/Engine/Source/Editor/VREditor/Teleporter",

  # todo: only for Source\Runtime\Engine
  "D:/BostonEngine/Engine/Source/Runtime/Net/Core/Private/Net/Core/PushModel/Types"
]


let ue5Defines: seq[string] = @[]

let defaultUndefines = @[
  # undefine __OBJC__ (for objective-c), idk why this is defined by default
  "__OBJC__"
]

proc createCompileArguments(module: ModuleInfo, modules: seq[ModuleInfo], uhtPaths: seq[string]): seq[string] =
  # result.add "-Wno-function_marked_override_not_overriding"
  # result.add "-Wno-function-marked-override-not-overriding"
  result.add defaultDefines.mapIt("-D" & it)

  case unrealVersion
  of V4_27:
    result.add ue4Defines.mapIt("-D" & it)
    result.add ue4Includes.mapIt("-I" & it.toNativePath)
  of V5_3:
    result.add ue5Defines.mapIt("-D" & it)
  result.add defaultUndefines.mapIt("-U" & it)

  for module in modules:
    result.add "-D" & module.apiDefine & "="

  for module in modules:
    if module.classes.isSome:
      result.add "-I" & module.classes.get.toNativePath
    if module.public.isSome:
      result.add "-I" & module.public.get.toNativePath

  result.add uhtPaths.mapIt("-I" & it.toNativePath)
  result.add "-I" & (enginePath / "Source").toNativePath
  result.add "-I" & (enginePath / "Source/Runtime").toNativePath
  result.add "-I" & (enginePath / "Source/Developer").toNativePath
  result.add "-I" & (enginePath / "Source/Editor").toNativePath

  if module.private.isSome:
    result.add "-I" & module.private.get.toNativePath

proc createCompileCommands(outputDir: string) =
  var modules: seq[ModuleInfo] = @[]
  var uhtPaths: seq[string] = @[]
  collectSourceModules(enginePath / "Source" / "Runtime", modules)
  collectSourceModules(enginePath / "Source" / "Developer", modules)
  collectSourceModules(enginePath / "Source" / "Editor", modules)
  collectSourceModules(enginePath / "Source" / "Programs", modules)
  collectUHTPaths(enginePath.getUhtRootPath, uhtPaths)

  var arr = newJArray()
  for module in modules:
    # echo module.path, ": ", module.name
    if shouldIgnore(module.path):
      echo "Ignoring module by path ", module.path
      continue
    if shouldIgnore(module.name):
      echo "Ignoring module by name ", module.name
      continue

    for file in module.sources:
      if shouldIgnore(file):
        echo "Ignoring file ", file
        continue

      var arguments = @[
        "clang++",
        cppVersion,
        "-I" & (enginePath / "Shaders/Shared").toNativePath
      ] & createCompileArguments(module, modules, uhtPaths)
      let directory = module.path.toNativePath
      arr.add %*{
        "file": file.toNativePath,
        "arguments": %* arguments,
        "directory": directory,
      }

  var result = arr.pretty
  writeFile("compile_commands.json", result)

createCompileCommands(enginePath)