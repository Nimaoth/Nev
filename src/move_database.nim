import std/[strutils, sequtils, sugar, options, json, streams, strformat, tables,
  deques, sets, algorithm]
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
from scripting_api as api import nil
import misc/[id, util, rect_utils, event, custom_logger, custom_async, fuzzy_matching,
  custom_unicode, delayed_task, myjsonutils, regex, timer, response, rope_utils, rope_regex, jsonex]
import text/custom_treesitter, text/indent
import config_provider, service
import text/[overlay_map, tab_map, wrap_map, diff_map, display_map]
import nimsumtree/[rope]

{.push gcsafe, raises: [].}

logCategory "moves"

type
  MoveImpl* = proc(rope: Rope, move: string, selections: openArray[Selection], count: int, includeEol: bool): seq[Selection] {.gcsafe, raises: [].}
  MoveDatabase* = ref object of Service
    moves: Table[string, MoveImpl]

func serviceName*(_: typedesc[MoveDatabase]): string = "MoveDatabase"

addBuiltinService(MoveDatabase)

method init*(self: MoveDatabase): Future[Result[void, ref CatchableError]] {.async: (raises: []).} =
  return ok()

proc applyMove*(self: MoveDatabase, rope: Rope, move: string, selections: openArray[Selection], count: int = 0, includeEol: bool = true): seq[Selection] =

  if move in self.moves:
    let impl = self.moves[move]
    return impl(rope, move, selections, count, includeEol)

  case move
  else:
    log lvlError, &"Unknown move '{move}'"
    return @selections

proc registerMove*(self: MoveDatabase, move: string, impl: MoveImpl) =
  self.moves[move] = impl
