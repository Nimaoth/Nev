import std/[options, json]
import nimsumtree/[rope]
import component, service
import text/display_map
import lisp

import scripting_api except TextDocumentEditor

export component

include dynlib_export

type MoveComponent* = ref object of Component
  targetColumn*: int = -1

type MoveFunction = proc(move: string, selections: openArray[Selection], count: int, args: openArray[LispVal], env: Env): seq[Selection] {.gcsafe, raises: [].}

# DLL API

{.push apprtl, gcsafe, raises: [].}
proc newMoveComponent*(services: Services, displayMap: DisplayMap, fallbackMoves: MoveFunction): MoveComponent
proc moveComponentApplyMove*(self: MoveComponent, selections: openArray[Range[Point]], move: string, count: int = 0, includeEol: bool = true, wrap: bool = true, options: JsonNode = nil): seq[Range[Point]]
proc getMoveComponent*(self: ComponentOwner): Option[MoveComponent]
{.pop.}

# Nice wrappers
proc applyMove*(self: MoveComponent, selections: openArray[Range[Point]], move: string, count: int = 0, includeEol: bool = true, wrap: bool = true, options: JsonNode = nil): seq[Range[Point]] {.inline.} = moveComponentApplyMove(self, selections, move, count, includeEol, wrap, options)
proc applyMove*(self: MoveComponent, selection: Range[Point], move: string, count: int = 0, includeEol: bool = true, wrap: bool = true, options: JsonNode = nil): Range[Point] {.inline.} =
  let res = moveComponentApplyMove(self, [selection], move, count, includeEol, wrap, options)
  if res.len > 0:
    return res[0]
  return selection

# Implementation
when implModule:
  import std/[tables, sequtils]
  import misc/[util, myjsonutils, custom_logger, rope_utils]
  import move_database
  import lisp

  logCategory "move-component"

  let MoveComponentId = componentGenerateTypeId()

  type MoveComponentImpl* = ref object of MoveComponent
    moveDatabase*: MoveDatabase
    displayMap*: DisplayMap
    fallbackMoves*: MoveFunction

  proc getMoveComponent*(self: ComponentOwner): Option[MoveComponent] {.gcsafe, raises: [].} =
    return self.getComponent(MoveComponentId).mapIt(it.MoveComponent)

  proc getMoveComponentChecked*(self: ComponentOwner): MoveComponent {.gcsafe, raises: [].} =
    return self.getComponent(MoveComponentId).mapIt(it.MoveComponent).get

  proc newMoveComponent*(services: Services, displayMap: DisplayMap, fallbackMoves: MoveFunction): MoveComponent =
    return MoveComponentImpl(
      typeId: MoveComponentId,
      moveDatabase: services.getServiceChecked(MoveDatabase),
      displayMap: displayMap,
      fallbackMoves: fallbackMoves,
    )

  proc moveComponentApplyMove*(self: MoveComponent, selections: openArray[Range[Point]], move: string, count: int = 0, includeEol: bool = true, wrap: bool = true, options: JsonNode = nil): seq[Range[Point]] =
    let self = self.MoveComponentImpl
    var env = Env()
    env["screen-lines"] = newNumber(100)
    if self.targetColumn != -1:
      env["target-column"] = newNumber(self.targetColumn)
    elif selections.len > 0:
      env["target-column"] = newNumber(selections[^1].b.column.int)
    else:
      env["target-column"] = newNumber(0)
    env["count"] = newNumber(count)
    env["include-eol"] = newBool(includeEol)
    env["wrap"] = newBool(wrap)
    # todo
    # env["ts?"] = newBool(not self.tsTree.isNil)
    # env["ts.to?"] = newBool(self.textObjectsQuery != nil and not self.tsTree.isNil)
    defer:
      env.clear()

    proc readOptions(env: var Env, options: JsonNode) =
      if options.kind == JObject:
        for (key, val) in options.fields.pairs:
          try:
            env[key] = val.jsonTo(LispVal)
          except CatchableError as e:
            log lvlError, "Failed to convert option " & key & " = " & $val & " to lisp value: " & e.msg
      else:
        log lvlError, "Invalid move options, expected object: " & $options

    if options != nil:
      if options.kind == JArray:
        for o in options.elems:
          env.readOptions(o)
      else:
        env.readOptions(options)

    let selections = selections.mapIt(it.toSelection)
    let res = self.moveDatabase.applyMove(self.displayMap, move, selections, self.fallbackMoves, env)
    return res.mapIt(it.toRange)
