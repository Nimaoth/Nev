import std/[json, jsonutils, sequtils, strutils, strformat, lexbase, unicode, streams, tables]
import plugin_runtime
import std/[strutils, unicode]

import strutils, tables, sequtils

type
  LispValKind = enum
    Nil, Number, Symbol, String, List, Array, Map, Func, Lambda, Macro

  Env = ref object
    parent: Env
    env: Table[string, LispVal]

  LispVal = ref object
    case kind: LispValKind
    of Nil:
      discard
    of Number:
      num: float
    of Symbol:
      sym: string
    of String:
      str: string
    of List, Array:
      elems: seq[LispVal]
    of Map:
      fields: OrderedTable[string, LispVal]
    of Func:
      name: string
      fn: proc (args: seq[LispVal]): LispVal
    of Lambda, Macro:
      params: seq[string]
      body: LispVal
      env: Env

proc `$`*(val: LispVal): string {.raises: [].} =
  case val.kind
  of Nil: $"nil"
  of Number:
    if val.num.int.float == val.num:
      $val.num.int
    else:
      $val.num
  of Symbol: val.sym
  of String: val.str
  of List: "(" & val.elems.mapIt($it).join(" ") & ")"
  of Array: "[" & val.elems.mapIt($it).join(" ") & "]"
  of Map:
    var res = "{"
    var i = 0
    for key, val in val.fields.pairs:
      if i > 0:
        res.add ", "
      inc i
      res.add key
      res.add ": "
      res.add $val
    res.add "} "
    res
  of Func: &"<native.{val.name}>"
  of Lambda: &"({val.params}) -> {val.body})"
  of Macro: &"!({val.params}) -> {val.body})"

proc newNil(): LispVal =
  LispVal(kind: Nil)

proc newNumber(n: float): LispVal =
  LispVal(kind: Number, num: n)

proc newSymbol(s: string): LispVal =
  LispVal(kind: Symbol, sym: s)

proc newString(s: string): LispVal =
  LispVal(kind: String, str: s)

proc newList(elems: seq[LispVal] = @[]): LispVal =
  LispVal(kind: List, elems: elems)

proc newArray(elems: seq[LispVal] = @[]): LispVal =
  LispVal(kind: Array, elems: elems)

proc newMap(fields: OrderedTable[string, LispVal] = initOrderedTable[string, LispVal]()): LispVal =
  LispVal(kind: Map, fields: fields)

proc newFunc(name: string, fn: proc(args: seq[LispVal]): LispVal): LispVal =
  LispVal(kind: Func, name: name, fn: fn)

proc newFunc(fn: proc(args: seq[LispVal]): LispVal): LispVal =
  LispVal(kind: Func, fn: fn)

proc newLambda(params: seq[string], body: LispVal, env: Env): LispVal =
  LispVal(kind: Lambda, params: params, body: body, env: env)

proc newMacro(params: seq[string], body: LispVal, env: Env): LispVal =
  LispVal(kind: Macro, params: params, body: body, env: env)

proc createChild(env: Env): Env =
  result = Env(parent: env)

proc `[]`(env: Env, key: string): LispVal =
  env.env.withValue(key, value):
    return value[]

  if env.parent != nil:
    return env.parent[key]

  return nil

proc `[]=`(env: Env, key: string, val: LispVal) =
  env.env[key] = val

proc set(env: Env, key: string, val: LispVal): bool =
  env.env.withValue(key, value):
    value[] = val
    return true

  if env.parent != nil:
    return env.parent.set(key, val)

  return false

proc toJsonHook*(val: LispVal, opt = initToJsonOptions()): JsonNode {.raises: [].} =
  case val.kind
  of Nil: newJNull()
  of Number:
    if val.num.int.float == val.num:
      newJInt(val.num.int)
    else:
      newJFloat(val.num)
  of Symbol: newJString(val.sym)
  of String: newJString(val.str)
  of List, Array: val.elems.toJson
  of Map:
    var res = newJObject()
    for key, value in val.fields.pairs:
      res[key] = value.toJson
    res
  of Func: newJString(&"<native.{val.name}>")
  of Lambda: newJString(&"({val.params}) -> {val.body})")
  of Macro: newJString(&"!({val.params}) -> {val.body})")

proc fromJsonHook*(val: var LispVal, jsonNode: JsonNode, opt = Joptions()) {.raises: [ValueError].} =
  case jsonNode.kind
  of JNull:
    val = newNil()
  of JBool:
    val = newNumber(if jsonNode.getBool: 1 else: 0)
  of JInt:
    val = newNumber(jsonNode.getInt.float)
  of JFloat:
    val = newNumber(jsonNode.getFloat)
  of JString:
    val = newString(jsonNode.getStr)
  of JObject:
    val = newMap()
    for key, value in jsonNode.fields.pairs:
      val.fields[key] = value.jsonTo(LispVal)
  of JArray:
    val = newArray(jsonNode.elems.mapIt(it.jsonTo(LispVal)))

type
  LispEventKind* = enum ## enumeration of all events that may occur when parsing
    lispError,          ## an error occurred during parsing
    lispEof,            ## end of file reached
    lispString,         ## a string literal
    lispSymbol,         ## a symbol
    lispInt,            ## an integer literal
    lispFloat,          ## a float literal
    lispTrue,           ## the value `true`
    lispFalse,          ## the value `false`
    lispNull,           ## the value `null`
    lispObjectStart,    ## start of an object: the `{` token
    lispObjectEnd,      ## end of an object: the `}` token
    lispArrayStart,     ## start of an array: the `[` token
    lispArrayEnd        ## end of an array: the `]` token
    lispListStart,      ## start of an array: the `(` token
    lispListEnd,        ## end of an array: the `)` token
    lispListColon,      ## : in list

  TokKind* = enum # must be synchronized with TLispEventKind!
    tkError,
    tkEof,
    tkString,
    tkSymbol,
    tkInt,
    tkFloat,
    tkTrue,
    tkFalse,
    tkNull,
    tkParenLe,
    tkParenRi,
    tkCurlyLe,
    tkCurlyRi,
    tkBracketLe,
    tkBracketRi,
    tkColon,
    tkComma,
    tkCommaAt,
    tkBacktick, # {()}@*789/?[<>]=+456-!#~|&.0123%;

  ParserState = enum
    stateEof, stateStart, stateObject, stateArray, stateList, stateExpectArrayComma,
    stateExpectObjectComma, stateExpectColon, stateExpectValue

  LispError* = enum       ## enumeration that lists all errors that can occur
    errNone,              ## no error
    errInvalidToken,      ## invalid token
    errStringExpected,    ## string expected
    errColonExpected,     ## `:` expected
    errCommaExpected,     ## `,` expected
    errBracketRiExpected, ## `]` expected
    errParenRiExpected,   ## `)` expected
    errCurlyRiExpected,   ## `}` expected
    errQuoteExpected,     ## `"` or `'` expected
    errEOC_Expected,      ## `*/` expected
    errEofExpected,       ## EOF expected
    errExprExpected       ## expr expected

  LispParser* = object of BaseLexer ## the parser object.
    a*: string
    tok*: TokKind
    kind: LispEventKind
    err: LispError
    state: seq[ParserState]
    filename: string
    rawStringLiterals: bool

  LispKindError* = object of ValueError ## raised by the `to` macro if the
                                        ## Lisp kind is incorrect.
  LispParsingError* = object of ValueError ## is raised for a Lisp error

const
  errorMessages*: array[LispError, string] = [
    "no error",
    "invalid token",
    "string expected",
    "':' expected",
    "',' expected",
    "']' expected",
    "')' expected",
    "'}' expected",
    "'\"' or \"'\" expected",
    "'*/' expected",
    "EOF expected",
    "expression expected"
  ]
  tokToStr: array[TokKind, string] = [
    "invalid token",
    "EOF",
    "string literal",
    "symbol",
    "int literal",
    "float literal",
    "true",
    "false",
    "nil",
    "(", ")", "{", "}", "[", "]", ":", ",", ",@", "`"
  ]

proc open*(my: var LispParser, input: Stream, filename: string; rawStringLiterals = false) =
  ## initializes the parser with an input stream. `Filename` is only used
  ## for nice error messages. If `rawStringLiterals` is true, string literals
  ## are kept with their surrounding quotes and escape sequences in them are
  ## left untouched too.
  lexbase.open(my, input)
  my.filename = filename
  my.state = @[stateStart]
  my.kind = lispError
  my.a = ""
  my.rawStringLiterals = rawStringLiterals

proc close*(my: var LispParser) {.inline.} =
  ## closes the parser `my` and its associated input stream.
  lexbase.close(my)

proc str*(my: LispParser): string {.inline.} =
  ## returns the character data for the events: `lispInt`, `lispFloat`,
  ## `lispString`
  assert(my.kind in {lispInt, lispFloat, lispString, lispSymbol})
  return my.a

proc getInt*(my: LispParser): BiggestInt {.inline.} =
  ## returns the number for the event: `lispInt`
  assert(my.kind == lispInt)
  return parseBiggestInt(my.a)

proc getFloat*(my: LispParser): float {.inline.} =
  ## returns the number for the event: `lispFloat`
  assert(my.kind == lispFloat)
  return parseFloat(my.a)

proc kind*(my: LispParser): LispEventKind {.inline.} =
  ## returns the current event type for the Lisp parser
  return my.kind

proc getColumn*(my: LispParser): int {.inline.} =
  ## get the current column the parser has arrived at.
  result = getColNumber(my, my.bufpos)

proc getLine*(my: LispParser): int {.inline.} =
  ## get the current line the parser has arrived at.
  result = my.lineNumber

proc getFilename*(my: LispParser): string {.inline.} =
  ## get the filename of the file that the parser processes.
  result = my.filename

proc errorMsg*(my: LispParser): string =
  ## returns a helpful error message for the event `lispError`
  assert(my.kind == lispError)
  result = "$1($2, $3) Error: $4" % [
    my.filename, $getLine(my), $getColumn(my), errorMessages[my.err]]

proc errorMsgExpected*(my: LispParser, e: string): string =
  ## returns an error message "`e` expected" in the same format as the
  ## other error messages
  result = "$1($2, $3) Error: $4" % [
    my.filename, $getLine(my), $getColumn(my), e & " expected"]

proc handleHexChar*(c: char, x: var int): bool {.inline.} =
  ## Converts `%xx` hexadecimal to the ordinal number and adds the result to `x`.
  ## Returns `true` if `c` is hexadecimal.
  ##
  ## When `c` is hexadecimal, the proc is equal to `x = x shl 4 + hex2Int(c)`.
  result = true
  case c
  of '0'..'9': x = (x shl 4) or (ord(c) - ord('0'))
  of 'a'..'f': x = (x shl 4) or (ord(c) - ord('a') + 10)
  of 'A'..'F': x = (x shl 4) or (ord(c) - ord('A') + 10)
  else:
    result = false

proc parseEscapedUTF16*(buf: cstring, pos: var int): int =
  result = 0
  #UTF-16 escape is always 4 bytes.
  for _ in 0..3:
    # if char in '0' .. '9', 'a' .. 'f', 'A' .. 'F'
    if handleHexChar(buf[pos], result):
      inc(pos)
    else:
      return -1

proc parseSymbol(my: var LispParser): TokKind =
  result = tkSymbol
  var pos = my.bufpos
  while true:
    case my.buf[pos]
    of ')', '}', ']', ',', ' ', '\n', ':':
      break
    of '\c':
      break
    # of '\L':
    #   break
    else:
      add(my.a, my.buf[pos])
      inc(pos)
  my.bufpos = pos # store back

proc parseString(my: var LispParser): TokKind =
  result = tkString
  var pos = my.bufpos + 1
  if my.rawStringLiterals:
    add(my.a, '"')
  while true:
    case my.buf[pos]
    of '\0':
      my.err = errQuoteExpected
      result = tkError
      break
    of '"':
      if my.rawStringLiterals:
        add(my.a, '"')
      inc(pos)
      break
    of '\\':
      if my.rawStringLiterals:
        add(my.a, '\\')
      case my.buf[pos+1]
      of '\\', '"', '\'', '/':
        add(my.a, my.buf[pos+1])
        inc(pos, 2)
      of 'b':
        add(my.a, '\b')
        inc(pos, 2)
      of 'f':
        add(my.a, '\f')
        inc(pos, 2)
      of 'n':
        add(my.a, '\L')
        inc(pos, 2)
      of 'r':
        add(my.a, '\C')
        inc(pos, 2)
      of 't':
        add(my.a, '\t')
        inc(pos, 2)
      of 'v':
        add(my.a, '\v')
        inc(pos, 2)
      of 'u':
        if my.rawStringLiterals:
          add(my.a, 'u')
        inc(pos, 2)
        var pos2 = pos
        var r = parseEscapedUTF16(cstring(my.buf), pos)
        if r < 0:
          my.err = errInvalidToken
          break
        # Deal with surrogates
        if (r and 0xfc00) == 0xd800:
          if my.buf[pos] != '\\' or my.buf[pos+1] != 'u':
            my.err = errInvalidToken
            break
          inc(pos, 2)
          var s = parseEscapedUTF16(cstring(my.buf), pos)
          if (s and 0xfc00) == 0xdc00 and s > 0:
            r = 0x10000 + (((r - 0xd800) shl 10) or (s - 0xdc00))
          else:
            my.err = errInvalidToken
            break
        if my.rawStringLiterals:
          let length = pos - pos2
          for i in 1 .. length:
            if my.buf[pos2] in {'0'..'9', 'A'..'F', 'a'..'f'}:
              add(my.a, my.buf[pos2])
              inc pos2
            else:
              break
        else:
          add(my.a, toUTF8(Rune(r)))
      else:
        # don't bother with the error
        add(my.a, my.buf[pos])
        inc(pos)
    of '\c':
      pos = lexbase.handleCR(my, pos)
      add(my.a, '\c')
    of '\L':
      pos = lexbase.handleLF(my, pos)
      add(my.a, '\L')
    else:
      add(my.a, my.buf[pos])
      inc(pos)
  my.bufpos = pos # store back

proc skip(my: var LispParser) =
  var pos = my.bufpos
  while true:
    case my.buf[pos]
    of ';':
      if true or my.buf[pos+1] == '/':
        # skip line comment:
        inc(pos, 2)
        while true:
          case my.buf[pos]
          of '\0':
            break
          of '\c':
            pos = lexbase.handleCR(my, pos)
            break
          of '\L':
            pos = lexbase.handleLF(my, pos)
            break
          else:
            inc(pos)
      elif my.buf[pos+1] == '*':
        # skip long comment:
        inc(pos, 2)
        while true:
          case my.buf[pos]
          of '\0':
            my.err = errEOC_Expected
            break
          of '\c':
            pos = lexbase.handleCR(my, pos)
          of '\L':
            pos = lexbase.handleLF(my, pos)
          of '*':
            inc(pos)
            if my.buf[pos] == '/':
              inc(pos)
              break
          else:
            inc(pos)
      else:
        break
    of ' ', '\t':
      inc(pos)
    of '\c':
      pos = lexbase.handleCR(my, pos)
    of '\L':
      pos = lexbase.handleLF(my, pos)
    else:
      break
  my.bufpos = pos

proc parseNumber(my: var LispParser) =
  var pos = my.bufpos
  if my.buf[pos] == '-':
    add(my.a, '-')
    inc(pos)
  if my.buf[pos] == '.':
    add(my.a, "0.")
    inc(pos)
  else:
    while my.buf[pos] in Digits:
      add(my.a, my.buf[pos])
      inc(pos)
    if my.buf[pos] == '.':
      add(my.a, '.')
      inc(pos)
  # digits after the dot:
  while my.buf[pos] in Digits:
    add(my.a, my.buf[pos])
    inc(pos)
  if my.buf[pos] in {'E', 'e'}:
    add(my.a, my.buf[pos])
    inc(pos)
    if my.buf[pos] in {'+', '-'}:
      add(my.a, my.buf[pos])
      inc(pos)
    while my.buf[pos] in Digits:
      add(my.a, my.buf[pos])
      inc(pos)
  my.bufpos = pos

proc parseName(my: var LispParser) =
  var pos = my.bufpos
  if my.buf[pos] in IdentStartChars:
    while my.buf[pos] in IdentChars:
      add(my.a, my.buf[pos])
      inc(pos)
  my.bufpos = pos

proc getTok*(my: var LispParser): TokKind =
  setLen(my.a, 0)
  skip(my) # skip whitespace, comments
  case my.buf[my.bufpos]
  of '-':
    if my.buf[my.bufpos + 1] != ' ':
      parseNumber(my)
      if {'.', 'e', 'E'} in my.a:
        result = tkFloat
      else:
        result = tkInt
    else:
        result = parseSymbol(my)
  of '0'..'9':
    parseNumber(my)
    if {'.', 'e', 'E'} in my.a:
      result = tkFloat
    else:
      result = tkInt
  of '"':
    result = parseString(my)
  of '[':
    inc(my.bufpos)
    result = tkBracketLe
  of '(':
    inc(my.bufpos)
    result = tkParenLe
  of '{':
    inc(my.bufpos)
    result = tkCurlyLe
  of ']':
    inc(my.bufpos)
    result = tkBracketRi
  of ')':
    inc(my.bufpos)
    result = tkParenRi
  of '}':
    inc(my.bufpos)
    result = tkCurlyRi
  of ',':
    inc(my.bufpos)
    if my.buf[my.bufpos] == '@':
      inc(my.bufpos)
      result = tkCommaAt
    else:
      result = tkComma
  of '`':
    inc(my.bufpos)
    result = tkBacktick
  of ':':
    inc(my.bufpos)
    result = tkColon
  of '\0':
    result = tkEof
  else:
    result = parseSymbol(my)
    case my.a
    of "nil": result = tkNull
    of "true": result = tkTrue
    of "false": result = tkFalse

  my.tok = result

proc raiseParseErr*(p: LispParser, msg: string) {.noinline, noreturn.} =
  ## raises an `ELispParsingError` exception.
  raise newException(LispParsingError, errorMsgExpected(p, msg))

proc eat*(p: var LispParser, tok: TokKind) =
  if p.tok == tok: discard getTok(p)
  else: raiseParseErr(p, tokToStr[tok])

proc parseLisp(p: var LispParser; depth = 0, depthLimit = 1024): LispVal =
  ## Parses JSON from a JSON Parser `p`.
  case p.tok
  of tkString:
    result = newString(move p.a)
    discard getTok(p)
  of tkSymbol:
    result = newSymbol(move p.a)
    discard getTok(p)
  of tkBacktick:
    discard getTok(p)
    result = newList(@[newSymbol("quasiquote"), parseLisp(p, depth + 1)])
  of tkColon:
    discard getTok(p)
    result = newSymbol(":")
  of tkComma:
    discard getTok(p)
    result = newList(@[newSymbol("unquote"), parseLisp(p, depth + 1)])
  of tkCommaAt:
    discard getTok(p)
    result = newList(@[newSymbol("unquote-splicing"), parseLisp(p, depth + 1)])
  of tkInt:
    try:
      result = newNumber(parseBiggestInt(p.a).float)
    except ValueError:
      raiseParseErr(p, "number too big")
    discard getTok(p)
  of tkFloat:
    try:
      result = newNumber(parseFloat(p.a))
    except ValueError:
      raiseParseErr(p, "number too big")
    discard getTok(p)
  of tkTrue:
    result = newNumber(1)
    discard getTok(p)
  of tkFalse:
    result = newNumber(0)
    discard getTok(p)
  of tkNull:
    result = newNil()
    discard getTok(p)
  of tkCurlyLe:
    if depth > depthLimit:
      raiseParseErr(p, "}")
    result = newMap()
    discard getTok(p)
    while p.tok != tkCurlyRi:
      if p.tok notin {tkString, tkSymbol}:
        raiseParseErr(p, "string literal as key")
      var key = p.a
      discard getTok(p)
      eat(p, tkColon)
      var val = parseLisp(p, depth+1)
      result.fields[key] = val
      if p.tok != tkComma: break
      discard getTok(p)
    eat(p, tkCurlyRi)
  of tkBracketLe:
    if depth > depthLimit:
      raiseParseErr(p, "]")
    result = newArray()
    discard getTok(p)
    while p.tok != tkBracketRi:
      result.elems.add(parseLisp(p, depth+1))
      if p.tok != tkComma: break
      discard getTok(p)
    eat(p, tkBracketRi)
  of tkParenLe:
    if depth > depthLimit:
      raiseParseErr(p, ")")
    result = newList()
    discard getTok(p)
    while p.tok != tkParenRi:
      result.elems.add(parseLisp(p, depth+1))
      if p.tok == tkParenRi: break
    eat(p, tkParenRi)
  else:
    raiseParseErr(p, "{")

iterator parseLispFragments*(s: Stream, filename: string = ""): LispVal =
  var p: LispParser
  p.open(s, filename)
  try:
    discard getTok(p) # read first token
    while p.tok != tkEof:
      yield p.parseLisp()
  finally:
    p.close()

proc parse(str: string): LispVal =
  var p: LispParser
  p.open(newStringStream(str), "repl")
  result = newList(@[newSymbol("list")])
  try:
    discard getTok(p) # read first token
    while p.tok != tkEof:
      result.elems.add p.parseLisp()
  finally:
    p.close()
  infof"parse -> {result}"

proc eval(expr: LispVal, env: var Env): LispVal

proc evalQuasiquote(expr: LispVal, env: var Env): LispVal =
  if expr.kind == List and expr.elems.len > 0:
    let head = expr.elems[0]
    if head.kind == Symbol:
      case head.sym
      of "unquote":
        return eval(expr.elems[1], env)
      of "unquote-splicing":
        raise newException(ValueError, "unquote-splicing not allowed here")  # must be handled inside list
  if expr.kind in {List, Array}:
    var resultElems: seq[LispVal] = @[]
    for el in expr.elems:
      if el.kind == List and el.elems.len > 0 and
         el.elems[0].kind == Symbol and el.elems[0].sym == "unquote-splicing":
        let spliceVal = eval(el.elems[1], env)
        if spliceVal.kind != expr.kind:
          raise newException(ValueError, "unquote-splicing must return a list")
        resultElems.add(spliceVal.elems)
      else:
        resultElems.add(evalQuasiquote(el, env))
    return newList(resultElems)
  elif expr.kind == Map:
    result = newMap()
    for key, el in expr.fields.pairs:
      if el.kind == List and el.elems.len > 0 and
         el.elems[0].kind == Symbol and el.elems[0].sym == "unquote-splicing":
        let spliceVal = eval(el.elems[1], env)
        if spliceVal.kind != Map:
          raise newException(ValueError, "unquote-splicing must return a map")
        for key2, val in spliceVal.fields.pairs:
          result.fields[key2] = val
      else:
        result.fields[key] = evalQuasiquote(el, env)
    return result
  else:
    return expr

proc eval(expr: LispVal, env: var Env): LispVal =

  case expr.kind
  of Nil, Number, String, Func, Lambda, Macro:
    return expr
  of Symbol:
    if expr.sym.startsWith("'"):
      return newSymbol(expr.sym[1..^1])
    result = env[expr.sym]
    if result == nil:
      raise newException(KeyError, "undefined symbol: '" & expr.sym & "'")

  of Array:
    return newArray(expr.elems.mapIt(eval(it, env)))

  of Map:
    result = newMap()
    for key, value in expr.fields.pairs:
      result.fields[key] = eval(value, env)

  of List:
    if expr.elems.len == 0:
      return expr

    let first = expr.elems[0]
    if first.kind == Symbol:
      case first.sym
      of "quote":
        return expr.elems[1]
      of "let":
        let sym = expr.elems[1]
        let value = eval(expr.elems[2], env)
        env[sym.sym] = value
        return value
      of "set":
        let sym = expr.elems[1]
        let value = eval(expr.elems[2], env)
        if not env.set(sym.sym, value):
          raise newException(KeyError, "undefined symbol: '" & expr.sym & "'")

        return value
      of "eval":
        let sub = expr.elems[1]
        let value = eval(sub, env)
        return eval(value, env)
      of "lambda":
        let params = expr.elems[1].elems.mapIt(it.sym)
        let body = expr.elems[2]
        return newLambda(params, body, env)
      of "defmacro":
        let name = expr.elems[1].sym
        let params = expr.elems[2].elems.mapIt(it.sym)
        let body = expr.elems[3]
        env[name] = newMacro(params, body, env)
        return env[name]
      of "quasiquote":
        return evalQuasiquote(expr.elems[1], env)
      of "if":
        let cond = eval(expr.elems[1], env)
        if cond.kind != Number:
          raise newException(ValueError, "Condition must be a number")
        if cond.num != 0:
          return eval(expr.elems[2], env)
        else:
          return eval(expr.elems[3], env)
      of "repeat":
        let name = expr.elems[1].sym
        let count = eval(expr.elems[2], env)
        if count.kind != Number:
          raise newException(ValueError, "Count must be a number")

        var res = newList()
        for i in 0..<count.num.int:
          if name != "":
            env[name] = newNumber(i.float)
          res.elems.add(eval(expr.elems[3], env))
        return res
      of "len":
        let container = eval(expr.elems[1], env)
        if container.kind == Map:
          return newNumber(container.fields.len.float)
        if container.kind in {List, Array}:
          return newNumber(container.elems.len.float)
        return newNumber(0)
      of ".=":
        if expr.elems.len < 4:
          raise newException(ValueError, ".= requires at least 3 arguments: container, key, value")
        let container = eval(expr.elems[1], env)
        let value = eval(expr.elems[^1], env)  # last argument is the value

        var current = container
        for i in 2..<(expr.elems.len - 2):
          let key = eval(expr.elems[i], env)
          if current.kind == Map:
            if key.kind == String:
              current = current.fields.getOrDefault(key.str)
            elif key.kind == Symbol:
              current = current.fields.getOrDefault(key.sym)
            else:
              raise newException(ValueError, "Key must be string or symbol")
          elif current.kind in {List, Array}:
            if key.kind == Number:
              let index = key.num.int
              if index in 0..current.elems.high:
                current = current.elems[index]
              else:
                raise newException(ValueError, &"Index out of bounds: {index} notin {0}..<{current.elems.len}")
            else:
              raise newException(ValueError, "Key must be int")
          else:
            raise newException(ValueError, &"Can't use . with {current.kind}")

        let finalKey = eval(expr.elems[^2], env)
        if current.kind == Map:
          if finalKey.kind == String:
            current.fields[finalKey.str] = value
          elif finalKey.kind == Symbol:
            current.fields[finalKey.sym] = value
          else:
            raise newException(ValueError, "Key must be string or symbol")
        elif current.kind in {List, Array}:
          if finalKey.kind == Number:
            let index = finalKey.num.int
            if index in 0..current.elems.high:
              current.elems[index] = value
            else:
              raise newException(ValueError, &"Index out of bounds: {index} notin {0}..<{current.elems.len}")
          else:
            raise newException(ValueError, "Key must be int")
        else:
          raise newException(ValueError, &"Can't use . with {current.kind}")
        return value
      of ".":
        if expr.elems.len < 3:
          raise newException(ValueError, ". requires at least 2 arguments: container, key")

        var current = eval(expr.elems[1], env)
        for i in 2..<expr.elems.len:
          let key = eval(expr.elems[i], env)
          if current.kind == Map:
            if key.kind == String:
              current = current.fields.getOrDefault(key.str)
            elif key.kind == Symbol:
              current = current.fields.getOrDefault(key.sym)
            else:
              raise newException(ValueError, "Key must be string or symbol")
          elif current.kind in {List, Array}:
            if key.kind == Number:
              let index = key.num.int
              if index in 0..current.elems.high:
                current = current.elems[index]
              else:
                raise newException(ValueError, &"Index out of bounds: {index} notin {0}..<{current.elems.len}")
            else:
              raise newException(ValueError, "Key must be int")
          else:
            raise newException(ValueError, &"Can't use . with {current.kind}")
        return current

    # Evaluate macro if first is a macro
    let fun = eval(first, env)
    case fun.kind
    of Macro:
      var newEnv = fun.env.createChild()
      for i in 0..<fun.params.len:
        let name = fun.params[i]
        if name.endsWith("..."):
          # capture remaining arguments
          var list = newList()
          for k in (i + 1)..<expr.elems.len:
            list.elems.add expr.elems[k]
          newEnv[name[0..^4]] = list
        else:
          newEnv[name] = expr.elems[i+1]  # unevaluated
      let expanded = eval(fun.body, newEnv)
      return eval(expanded, env)  # evaluate expanded result
    of Func, Lambda:
      let args = expr.elems[1..^1].mapIt(eval(it, env))
      case fun.kind
      of Func:
        return fun.fn(args)
      of Lambda:
        var newEnv = fun.env.createChild()
        for i in 0..<fun.params.len:
          newEnv[fun.params[i]] = args[i]
        return eval(fun.body, newEnv)
      else:
        discard
    else:
      raise newException(ValueError, "not a function or macro")

var globalEnv: Env = Env()

# Environment
proc baseEnv(): Env =
  result = Env()
  result["&"] = newFunc("join", proc(args: seq[LispVal]): LispVal =
    newString(args.foldl(a & $b, "")))
  result["+"] = newFunc("+", proc(args: seq[LispVal]): LispVal =
    newNumber(args.foldl(a + b.num, 0.0)))
  result["-"] = newFunc("-", proc(args: seq[LispVal]): LispVal =
    newNumber(args[0].num - args[1].num))
  result["*"] = newFunc("*", proc(args: seq[LispVal]): LispVal =
    newNumber(args.foldl(a * b.num, 1.0)))
  result["/"] = newFunc("/", proc(args: seq[LispVal]): LispVal =
    newNumber(args[0].num / args[1].num))
  result[">"] = newFunc(">", proc(args: seq[LispVal]): LispVal =
    newNumber(if args[0].num > args[1].num: 1 else: 0))
  result["<"] = newFunc("<", proc(args: seq[LispVal]): LispVal =
    newNumber(if args[0].num < args[1].num: 1 else: 0))
  result["list"] = newFunc("list", proc(args: seq[LispVal]): LispVal =
    newList(args))
  result["do"] = newFunc("do", proc(args: seq[LispVal]): LispVal =
    if args.len > 0:
      args.last
    else:
      newNil())
  result["head"] = newFunc("head", proc(args: seq[LispVal]): LispVal =
    if args[0].kind != List: raise newException(ValueError, "head needs list")
    else: args[0].elems[0])
  result["tail"] = newFunc("tail", proc(args: seq[LispVal]): LispVal =
    if args[0].kind != List: raise newException(ValueError, "tail needs list")
    else: newList(args[0].elems[1..^1]))
  result["cons"] = newFunc("cons", proc(args: seq[LispVal]): LispVal =
    if args[1].kind != List: raise newException(ValueError, "cons needs list")
    else: newList(@[args[0]] & args[1].elems))
  result["eq"] = newFunc("eq", proc(args: seq[LispVal]): LispVal =
    if args[0].kind == args[1].kind and $args[0] == $args[1]: newNumber(1) else: newNumber(0))

  result["info"] = newFunc("info", proc(args: seq[LispVal]): LispVal =
    var str = ""
    for i, arg in args:
      if i > 0:
        str.add " "
      str.add $arg
    infof"{str}"
  )

  result["clear-global-env"] = newFunc("clear-global-env", proc(args: seq[LispVal]): LispVal =
    globalEnv = baseEnv()
  )

  result["echo"] = newFunc("echo", proc(args: seq[LispVal]): LispVal =
    var str = ""
    for i, arg in args:
      if i > 0:
        str.add " "
      str.add $arg
    echo str
  )

  result["build-str"] = newFunc("build-str", proc(args: seq[LispVal]): LispVal =
    var str = ""
    for i, arg in args:
      str.add $arg
    return newString(str)
  )

  result["join-str"] = newFunc("join-str", proc(args: seq[LispVal]): LispVal =
    if args.len < 1: raise newException(ValueError, "join-str needs a seperator")
    if args[0].kind notin {String, Symbol}: raise newException(ValueError, "join-str needs a seperator")
    let sep = $args[0]
    var str = ""
    for i in 1..args.high:
      if i > 1:
        str.add sep
      str.add $args[i]
    return newString(str)
  )

  result["run-command"] = newFunc("run-command", proc(args: seq[LispVal]): LispVal =
    if args.len < 1: raise newException(ValueError, ": needs a command")
    if args[0].kind != Symbol: raise newException(ValueError, ": needs a command")
    let command = args[0].sym
    var arg = ""
    for i in 1..args.high:
      arg.add " "
      arg.add $args[i].toJson
    infof"run script action '{command}{arg}'"
    let res = scriptRunAction(command, arg)
    return res.jsonTo(LispVal)
  )

  result["add-command-raw"] = newFunc("add-command-raw", proc(args: seq[LispVal]): LispVal =
    if args.len < 4:
      raise newException(ValueError, &"Too few arguments, expected 4, got {args.len}")

    let context = args[0].sym
    let name = args[1].sym
    let active = args[2].num != 0
    let cb = args[3]
    let documentationStr = ""
    var params: seq[(string, string)] = @[]
    var returnType = ""

    if cb.kind != Lambda:
      raise newException(ValueError, "Callback must be a lambda")

    proc wrapper(args: JsonNode): JsonNode =
      var env = baseEnv()
      try:
        if args.kind != JArray:
          raise newException(ValueError, &"Args must be an array, got {args}")
        if args.elems.len != cb.params.len:
          raise newException(ValueError, &"Wrong number of arguments, expected {cb.params.len}, got {args.elems.len}")

        var newEnv = cb.env.createChild()
        for i in 0..<cb.params.len:
          newEnv[cb.params[i]] = args[i].jsonTo(LispVal)
        return eval(cb.body, newEnv).toJson()
      except:
        infof"Failed to call lisp callback: {getCurrentExceptionMsg()}"
        return newJNull()

    scriptActions[name] = wrapper
    addScriptAction(name, documentationStr, params, returnType, active, context, true)
  )

globalEnv = baseEnv()

proc evalSelection*(editor: TextDocumentEditor) {.exposeActive("editor.text", "eval-selection").} =
  let text = editor.getText(editor.selection)
  infof"leval selected '{text}'"
  try:
    let expr = parse(text)
    let result = eval(expr, globalEnv)
    infof"-> {result}"
  except CatchableError as e:
    infof"Error: {e.msg}"

proc leval*(code: JsonNode) {.expose("leval").} =
  infof"leval '{code}'"
  case code.kind
  of JString:
    infof"eval '{code.getStr}'"
    try:
      let expr = parse(code.getStr)
      let result = eval(expr, globalEnv)
      infof"-> {result}"
    except CatchableError as e:
      infof"Error: {e.msg}"
  else:
    infof"invalid code: {code}"

proc evalFile*(path: string) {.expose("eval-file").} =
  infof"leval file '{path}'"
  let text = readFileSync(path)
  try:
    let expr = parse(text)
    let result = eval(expr, globalEnv)
    # infof"-> {result}"
  except CatchableError as e:
    infof"Error: {e.msg}"

proc postInitialize*(): bool {.wasmexport.} =
  infof "post initialize lisp"
  if getOption("lisp.eval-default-files", false):
    let defaultFiles = getOption("lisp.default-files", newSeq[string]())
    for file in defaultFiles:
      evalFile(file)
  return true

when defined(wasm):
  include plugin_runtime_impl
