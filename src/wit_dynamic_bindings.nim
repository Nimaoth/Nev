import std/[os, strutils, strformat, sequtils, unicode]
import wit_parser

type IdentifierCase* = enum Camel, Pascal, Kebab, Snake, ScreamingSnake

proc splitCase*(s: string): tuple[cas: IdentifierCase, parts: seq[string]] =
  if s == "":
    return (IdentifierCase.Camel, @[])

  if s.find('_') != -1:
    result.cas = IdentifierCase.Snake
    result.parts = s.split('_').mapIt(toLower(it))
    for r in s.runes:
      if r != '_'.Rune and not r.isLower:
        result.cas = IdentifierCase.ScreamingSnake
        break

  elif s.find('-') != -1:
    result.cas = IdentifierCase.Kebab
    result.parts = s.split('-').mapIt(toLower(it))
  else:
    if s[0].isUpperAscii:
      result.cas = IdentifierCase.Pascal
    else:
      result.cas = IdentifierCase.Camel

    result.parts.add ""
    for r in s.runes:
      if not r.isLower and result.parts[^1].len > 0:
        result.parts.add ""
      result.parts[^1].add(toLower(r))

proc joinCase*(parts: seq[string], cas: IdentifierCase): string =
  if parts.len == 0:
    return ""
  case cas
  of IdentifierCase.Camel:
    parts[0] & parts[1..^1].mapIt(it.capitalize).join("")
  of IdentifierCase.Pascal:
    parts.mapIt(it.capitalize).join("")
  of IdentifierCase.Kebab:
    parts.join("-")
  of IdentifierCase.Snake:
    parts.join("_")
  of IdentifierCase.ScreamingSnake:
    parts.mapIt(toUpper(it)).join("_")

proc cycleCase*(s: string): string =
  if s.len == 0:
    return s
  let (cas, parts) = s.splitCase()
  let nextCase = if cas == IdentifierCase.high:
    IdentifierCase.low
  else:
    cas.succ
  return parts.joinCase(nextCase)

type Output = object
  buffer: string
  switchBuffer: string

proc toCamelCase(str: string): string =
  return str.splitCase.parts.joinCase(Camel)

proc toPascalCase(str: string): string =
  let i = str.find('.')
  if i != -1:
    return str[(i + 1)..^1].splitCase.parts.joinCase(Pascal)
  return str.splitCase.parts.joinCase(Pascal)

proc generateType(o: var Output, wit: WitModule, t: TypeIdx)

proc generateType(o: var Output, wit: WitModule, t: Type) =
  case t.kind
  of TKVoid: o.buffer.add("void")
  of TKBool: o.buffer.add("bool")
  of TKChar: o.buffer.add("char")
  of TKString: o.buffer.add("string")
  of TKInt:
    if not t.signed:
      o.buffer.add("u")
    o.buffer.add("int")
    o.buffer.add $(t.bytes * 8)
  of TKFloat:
    o.buffer.add("float")
    o.buffer.add $(t.bytes * 8)
  of TKList:
    o.buffer.add("seq[")
    o.generateType(wit, t.elem)
    o.buffer.add("]")
  of TKOption:
    o.buffer.add("Option[")
    o.generateType(wit, t.elem)
    o.buffer.add("]")
  of TKResult:
    o.buffer.add("Result[")
    o.generateType(wit, t.ok)
    o.buffer.add(", ")
    o.generateType(wit, t.err)
    o.buffer.add("]")
  of TKTuple:
    o.buffer.add("(")
    for i, t2 in t.elems:
      o.generateType(wit, t2)
      o.buffer.add(", ")
    o.buffer.add(")")

  of TKUser:
    o.buffer.add "plugin_api."
    o.buffer.add(t.name.toPascalCase)

  of TKUnresolved:
    o.buffer.add "unresolved.plugin_api."
    o.buffer.add(t.name.toPascalCase)

proc generateType(o: var Output, wit: WitModule, t: TypeIdx) =
  o.generateType(wit, wit.getType(t))

proc containsResource(wit: WitModule, t: TypeIdx): bool =
  let typ = wit.getType(t)
  case typ.kind
  of TKList:
    return containsResource(wit, typ.elem)
  of TKOption:
    return containsResource(wit, typ.elem)
  of TKResult:
    return containsResource(wit, typ.ok) or containsResource(wit, typ.err)
  of TKTuple:
    for t2 in typ.elems:
      if containsResource(wit, t2):
        return true
  of TKUser:
    let item = wit.getItem(typ)
    return item.kind == IKResource
  else:
    return false
  return false

proc generateFunction(o: var Output, wit: WitModule, interfac: string, name: string, fun: FuncSig, self: TypeIdx = 0.TypeIdx) =
  if wit.containsResource(fun.result):
    echo "Skip ", name, ", ", fun
    return
  for i, p in fun.params:
    if wit.containsResource(p.typ):
      echo "Skip ", name, ", ", fun
      return

  o.buffer.add &"proc {interfac.toCamelCase}{name.toPascalCase}*(instance: ptr InstanceData, "
  o.buffer.add "args: LispVal, namedArgs: LispVal"
  o.buffer.add "): LispVal =\n  "
  if fun.result.int != 0:
    o.buffer.add "let res = "

  o.buffer.add "instance."
  o.buffer.add interfac.toCamelCase & name.toPascalCase
  o.buffer.add "("

  var argsOffset = 0
  if self.int != 0:
    argsOffset = 1
    o.buffer.add &"getArg(args, namedArgs, 0, \"self\", "
    o.generateType(wit, self)
    o.buffer.add "), "

  for i, p in fun.params:
    o.buffer.add &"getArg(args, namedArgs, {i + argsOffset}, \"{p.name}\", "
    o.generateType(wit, p.typ)
    o.buffer.add "), "
  o.buffer.add ")"
  o.buffer.add "\n"
  if fun.result.int != 0:
    o.buffer.add "  return res.toJson().jsonTo(LispVal)\n"
  else:
    o.buffer.add "  return newNil()\n"

  o.switchBuffer.add &"  of \"{interfac}.{name}\": {interfac.toCamelCase}{name.toPascalCase}(instance, args, namedArgs)\n"

proc generateInterface(o: var Output, wit: WitModule, decl: Decl) =
  for item in decl.body:
    if item.kind == IKFunc:
      o.generateFunction(wit, decl.name, item.name, item.funcSig)
    # elif item.kind == IKResource:
    #   for m in item.methods:
    #     o.generateFunction(wit, decl.name.toCamelCase, m.name, m.sig, item.typ)

proc main() =
  let path = "wit/v0/api.wit"
  let contents = readFile(path)
  let module = parseWitModule(contents)

  var o = Output()

  o.buffer.add "import std/[options, json, jsonutils, tables]\n"
  o.buffer.add "import plugin_api, lisp\n\n"
  o.buffer.add """
{.used.}

proc getArg(args: LispVal, namedArgs: LispVal, index: int, name: string, T: typedesc): T =
  if args != nil and index < args.elems.len:
    return args.elems[index].toJson().jsonTo(T)
  if namedArgs != nil and name in namedArgs.fields:
    return namedArgs.fields[name].toJson().jsonTo(T)
  return T.default

"""

  let world = module.getWorld("plugin")
  if world != nil:
    echo "Generate world ", world[].name
    for item in world.body:
      if item.kind == IKImport:
        echo "Generate interface ", item.name
        let interfac = module.getInterface(item.name)
        if interfac != nil:
          o.generateInterface(module, interfac[])

  o.buffer.add "proc dispatchDynamic*(instance: ptr InstanceData, name: string, args: LispVal, namedArgs: LispVal): LispVal =\n"
  o.buffer.add "  case name\n"
  o.buffer.add o.switchBuffer
  o.buffer.add "  else: echo(\"Unknown API '\", name, \"'\"); newNil()\n"

  writeFile("src/plugin_api/plugin_api_dynamic.nim", o.buffer)

main()
