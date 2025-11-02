import std/[os, sequtils, strutils, tables, strformat]

type
  TokenKind* = enum
    tkIdent, tkNumber, tkString, tkArrow, tkSymbol, tkColon, tkSemicolon, tkComma, tkPeriod, tkBraceL, tkBraceR, tkParenL, tkParenR, tkLess, tkGreater, tkComment, tkEof

  Token* = object
    kind*: TokenKind
    text*: string
    line*: int
    lines*: int = 1
    col*: int

  WitModule* = object
    packageName*: string
    types*: seq[Type]
    decls*: seq[Decl]

  DeclKind* = enum
    DKInterface, DKWorld, DKPackage, DKImport, DKExport

  Decl* = object
    kind*: DeclKind
    name*: string
    docs*: string
    body*: seq[Item]

  TypeKind* = enum
    TKVoid, TKInt, TKFloat, TKString, TKBool, TKChar, TKList, TKOption, TKResult, TKTuple, TKUser, TKUnresolved

  TypeIdx* = distinct int

  Type* = object
    case kind*: TypeKind
    of TKUser, TKUnresolved:
      name*: string
      declIndex*: int
      itemIndex*: int
    of TKList, TKOption:
      elem*: TypeIdx
    of TKResult:
      ok*: TypeIdx
      err*: TypeIdx
    of TKTuple:
      elems*: seq[TypeIdx]
    of TKInt, TKFloat:
      signed*: bool
      bytes*: int
    of TKVoid, TKSTring, TKBool, TKChar:
      discard

  ItemKind* = enum
    IKRecord, IKResource, IKEnum, IKFlags, IKUse, IKFunc, IKImport, IKExport, IKOther

  Item* = object
    name*: string
    docs*: string
    typ*: TypeIdx
    case kind*: ItemKind
    of IKRecord:
      fields*: seq[Field]
    of IKResource:
      methods*: seq[Method]
    of IKEnum, IKFlags:
      variants*: seq[string]
    of IKUse:
      useModule*: string
      useItems*: seq[string]
    of IKFunc:
      funcSig*: FuncSig
    of IKImport, IKExport, IKOther:
      discard

  Field* = object
    name*: string
    typ*: TypeIdx

  Method* = object
    name*: string
    docs*: string
    isStatic*: bool
    isConstructor*: bool
    sig*: FuncSig

  FuncSig* = object
    params*: seq[Field]
    result*: TypeIdx

  Parser* = object
    src: string
    idx: int
    line: int
    col: int
    eofToken: Token
    tokens: seq[Token]
    module: WitModule
    currentInterface: string
    typeScope: Table[string, TypeIdx]
    importMap: Table[string, string] # maps name to interface where it comes from in current scope

proc `$`*(t: TypeIdx): string {.borrow.}

proc `$`*(p: Item): string =
  echo p.kind, ": ", p.name, "  -  ", p.docs
  case p.kind
  of IKRecord:
    echo "  ", p.fields
  of IKResource:
    echo "  ", p.methods
  of IKEnum, IKFlags:
    echo "  ", p.variants
  of IKUse:
    echo "  ", p.useModule
    echo "  ", p.useItems
  of IKFunc:
    echo "  ", p.funcSig
  of IKImport, IKExport, IKOther:
    discard

proc `$`*(p: WitModule): string =
  echo "module: ", p.packageName
  echo "types:"
  for i, t in p.types:
    echo "  ", i, ": ", t
  echo "decls:"
  for i, t in p.decls:
    echo "  ", i, ":\n", ($t).indent(2)

proc `$`*(p: Parser): string =
  echo "types: ", p.typeScope
  echo p.module

proc newParser*(s: string): Parser =
  result = Parser(src: s, idx: 0, line: 1, col: 1, eofToken: Token(kind: tkEof, text: "", line: 1, col: 1), tokens: @[])
  result.module.types.add(Type(kind: TKVoid))
  result.module.types.add(Type(kind: TKBool))
  result.module.types.add(Type(kind: TKChar))
  result.module.types.add(Type(kind: TKString))
  result.module.types.add(Type(kind: TKInt, signed: false, bytes: 1))
  result.module.types.add(Type(kind: TKInt, signed: false, bytes: 2))
  result.module.types.add(Type(kind: TKInt, signed: false, bytes: 4))
  result.module.types.add(Type(kind: TKInt, signed: false, bytes: 8))
  result.module.types.add(Type(kind: TKInt, signed: true, bytes: 1))
  result.module.types.add(Type(kind: TKInt, signed: true, bytes: 2))
  result.module.types.add(Type(kind: TKInt, signed: true, bytes: 4))
  result.module.types.add(Type(kind: TKInt, signed: true, bytes: 8))
  result.module.types.add(Type(kind: TKFloat, bytes: 4))
  result.module.types.add(Type(kind: TKFloat, bytes: 8))

# --- Lexer ---------------------------------------------------------------
proc isIdentChar(c: char): bool =
  result = c in {'a'..'z', 'A'..'Z', '0'..'9', '-'}

proc getType*(self: WitModule, idx: TypeIdx): Type =
  return self.types[idx.int]

proc getItem*(self: WitModule, t: Type): Item =
  assert t.kind == TKUser
  return self.decls[t.declIndex].body[t.itemIndex]

proc lex(s: string): seq[Token] =
  var i = 0
  var line = 1
  var col = 0
  while i < s.len:
    let c = s[i]
    if c == '\n':
      inc line
      col = 0
      i.inc
      continue
    elif c in Whitespace:
      i.inc; col.inc
      continue
    # comments: // and ///
    elif c == '/' and i+1 < s.len and s[i+1] == '/':
      # consume till end of line
      i.inc
      i.inc
      col += 2
      var start = i
      while start < s.len and s[start] == '/':
        inc start
      if start < s.len and s[start] == ' ':
        inc start
      while i < s.len and s[i] != '\n':
        i.inc; col.inc
      let txt = s.substr(start, i - 1)
      if result.len > 0 and result[^1].kind == tkComment and result[^1].line + result[^1].lines == line:
        # merge with previous comment token
        result[^1].text.add " "
        result[^1].text.add txt
        result[^1].lines.inc()
      else:
        result.add Token(kind: tkComment, text: txt, line: line, col: start)
      continue
    elif c == '"':
      let startLine = line; let startCol = col
      var j = i+1
      var strbuf = ""
      while j < s.len and s[j] != '"':
        if s[j] == '\\' and j+1 < s.len:
          strbuf.add s[j]
          j.inc
          strbuf.add s[j]
        else:
          strbuf.add s[j]
        j.inc
      if j >= s.len:
        result.add Token(kind: tkString, text: strbuf, line: startLine, col: startCol)
        i = j
        col = 1
      else:
        result.add Token(kind: tkString, text: strbuf, line: startLine, col: startCol)
        col += (j - i + 1)
        i = j+1
      continue
    elif c == '-' and i+1 < s.len and s[i+1] == '>':
      result.add Token(kind: tkArrow, text: "->", line: line, col: col)
      i += 2; col += 2
      continue
    elif isIdentChar(c):
      let start = i; let startCol = col; let startLine = line
      var j = i
      while j < s.len and isIdentChar(s[j]): j.inc
      let txt = s.substr(start, j - 1)
      result.add Token(kind: tkIdent, text: txt, line: startLine, col: startCol)
      col += j - i
      i = j
      continue
    elif c.isDigit:
      let start = i; let startCol = col; let startLine = line
      var j = i
      while j < s.len and s[j].isDigit: j.inc
      let txt = s.substr(start, j - 1)
      result.add Token(kind: tkNumber, text: txt, line: startLine, col: startCol)
      col += j - i
      i = j
      continue
    elif c == ':':
      result.add Token(kind: tkColon, text: ":", line: line, col: col)
      col += 1
      i += 1
      continue
    elif c == ';':
      result.add Token(kind: tkSemicolon, text: ";", line: line, col: col)
      col += 1
      i += 1
      continue
    elif c == ',':
      result.add Token(kind: tkComma, text: ",", line: line, col: col)
      col += 1
      i += 1
      continue
    elif c == '.':
      result.add Token(kind: tkPeriod, text: ".", line: line, col: col)
      col += 1
      i += 1
      continue
    elif c == '(':
      result.add Token(kind: tkParenL, text: "(", line: line, col: col)
      col += 1
      i += 1
      continue
    elif c == ')':
      result.add Token(kind: tkParenR, text: ")", line: line, col: col)
      col += 1
      i += 1
      continue
    elif c == '{':
      result.add Token(kind: tkBraceL, text: "{", line: line, col: col)
      col += 1
      i += 1
      continue
    elif c == '}':
      result.add Token(kind: tkBraceR, text: "}", line: line, col: col)
      col += 1
      i += 1
      continue
    elif c == '<':
      result.add Token(kind: tkLess, text: "<", line: line, col: col)
      col += 1
      i += 1
      continue
    elif c == '>':
      result.add Token(kind: tkGreater, text: ">", line: line, col: col)
      col += 1
      i += 1
      continue

    else:

      # symbols
      result.add Token(kind: tkSymbol, text: $c, line: line, col: col)
      i.inc; col.inc
      continue
  result.add Token(kind: tkEof, text: "", line: line, col: col)

# --- Parser helpers -----------------------------------------------------
proc peek(p: var Parser): Token =
  result = p.tokens[p.idx]

proc skip(p: var Parser) =
  inc p.idx

proc current(p: var Parser): lent Token =
  if p.idx < p.tokens.len:
    return p.tokens[p.idx]
  else:
    return p.eofToken

proc parseError(p: var Parser, s: string) =
  raise newException(ValueError, $p.current.line & ":" & $p.current.col & ": " & s)

proc expectSym(p: var Parser, s: string) =
  if p.idx >= p.tokens.len:
    p.parseError("expected symbol '" & s & "' got eof")
  if p.current.kind != tkSymbol or p.current.text != s:
    p.parseError("expected symbol '" & s & "' got: '" & p.current.text & "'")
  p.skip()

proc expectIdent(p: var Parser): string =
  if p.idx >= p.tokens.len:
    p.parseError("expected identifier, got eof")
  if p.current.kind != tkIdent:
    p.parseError("expected identifier, got: '" & p.current.text & "'")
  result = p.current.text
  p.skip()

proc expect(p: var Parser, kind: TokenKind, txt: string = "") =
  if p.current.kind == kind and (txt == "" or p.current.text == txt):
    inc p.idx
  else:
    p.parseError("expected " & $kind & ", got: '" & p.current.text & "'")

proc eat(p: var Parser, kind: TokenKind, txt: string = ""): bool =
  if p.current.kind == kind and (txt == "" or p.current.text == txt):
    inc p.idx
    return true
  return false

proc resolveType*(p: var Parser, name: string): TypeIdx =
  case name
  of "void": return 0.TypeIdx
  of "bool": return 1.TypeIdx
  of "char": return 2.TypeIdx
  of "string": return 3.TypeIdx
  of "u8": return 4.TypeIdx
  of "u16": return 5.TypeIdx
  of "u32": return 6.TypeIdx
  of "u64": return 7.TypeIdx
  of "s8": return 8.TypeIdx
  of "s16": return 9.TypeIdx
  of "s32": return 10.TypeIdx
  of "s64": return 11.TypeIdx
  of "f32": return 12.TypeIdx
  of "f64": return 13.TypeIdx
  else:
    let isFullyQualified = name.find('.') != -1
    if isFullyQualified:
      if p.typeScope.contains(name):
        return p.typeScope[name]
      result = p.module.types.len.TypeIdx
      p.module.types.add(Type(kind: TKUnresolved, name: name))
      p.typeScope[name] = result
    else:
      if name notin p.importMap:
        echo &"{p.current.line}:{p.current.col} Unknown symbol '{name}'"
        return 0.TypeIdx
      let currentInterface = p.importMap[name]
      let fullyQualifiedName = currentInterface & "." & name
      if p.typeScope.contains(fullyQualifiedName):
        return p.typeScope[fullyQualifiedName]
      result = p.module.types.len.TypeIdx
      p.module.types.add(Type(kind: TKUnresolved, name: fullyQualifiedName))
      p.typeScope[fullyQualifiedName] = result

proc defineUserType(p: var Parser, name: string, declIndex: int, itemIndex: int): TypeIdx =
  let idx = p.resolveType(name)
  p.module.types[idx.int] = Type(kind: TKUser, name: p.module.types[idx.int].name, declIndex: declIndex, itemIndex: itemIndex)
  return idx

proc parseType(p: var Parser): TypeIdx =
  # parse name or generic type like list<string> or tuple<a, b>
  if p.current.kind == tkIdent:
    let nm = expectIdent(p)
    if eat(p, tkLess):
      var args: seq[TypeIdx] = @[]
      while true:
        if eat(p, tkGreater):
          break
        args.add parseType(p)
        if eat(p, tkComma):
          continue
        elif eat(p, tkGreater):
          break
        else:
          break
      # map common generic-like names to concrete Type kinds
      if nm == "list":
        if args.len > 0:
          p.module.types.add Type(kind: TKList, elem: args[0])
          return p.module.types.high.TypeIdx
        else:
          p.module.types.add Type(kind: TKList, elem: 0.TypeIdx)
          return p.module.types.high.TypeIdx
      elif nm == "option":
        if args.len > 0:
          p.module.types.add Type(kind: TKOption, elem: args[0])
          return p.module.types.high.TypeIdx
        else:
          p.module.types.add Type(kind: TKOption, elem: 0.TypeIdx)
          return p.module.types.high.TypeIdx
      elif nm == "result":
        var okt = 0.TypeIdx
        var errt = 0.TypeIdx
        if args.len > 0: okt = args[0]
        if args.len > 1: errt = args[1]
        p.module.types.add Type(kind: TKResult, ok: okt, err: errt)
        return p.module.types.high.TypeIdx
      elif nm == "tuple":
        p.module.types.add Type(kind: TKTuple, elems: args)
        return p.module.types.high.TypeIdx
      else:
        assert false
        p.module.types.add Type(kind: TKTuple, elems: args)
        return p.module.types.high.TypeIdx
    else:
      return p.resolveType(nm)
  # elif p.current.kind == tkSymbol and p.current.text == "(":
  #   # parenthesized tuple-like type (a, b)
  #   p.expect(tkParenL)
  #   var elems: seq[Type] = @[]
  #   while true:
  #     if eat(p, tkParenR):
  #       break
  #     elems.add parseType(p)
  #     if eat(p, tkComma):
  #       continue
  #     elif eat(p, tkParenR):
  #       break
  #     else:
  #       break
  #   return Type(kind: TKTuple, elems: elems)
  else:
    # fallback: consume one token and make it a name
    # return Type(kind: TKUser, name: p.current.text)
    return TypeIdx(0)

proc parseParams(p: var Parser): seq[Field] =
  var params: seq[Field] = @[]
  expect(p, tkParenL)
  while true:
    if eat(p, tkParenR):
      break
    let nm = expectIdent(p)
    expect(p, tkColon)
    let tpe = parseType(p)
    params.add(Field(name: nm, typ: tpe))
    if eat(p, tkComma):
      continue
    elif eat(p, tkParenR):
      break
    else:
      break
  result = params

proc parseFuncSig(p: var Parser): FuncSig =
  var sig = FuncSig(params: @[], result: 0.TypeIdx)
  sig.params = parseParams(p)
  if eat(p, tkArrow, "") or (p.tokens.len > 0 and p.current.kind == tkSymbol and p.current.text == "->"):
    if p.tokens.len > 0 and p.current.kind == tkSymbol and p.current.text == "->": p.tokens.delete(0)
    sig.result = parseType(p)
  return sig

proc parseRecord(p: var Parser, name: string, docs: string, declIndex: int, itemIndex: int): Item =
  p.importMap[name] = p.currentInterface
  var it = Item(kind: IKRecord)
  it.name = name
  it.fields = @[]
  it.docs = docs
  p.expect(tkBraceL)
  while true:
    if eat(p, tkBraceR):
      break
    let fldName = expectIdent(p)
    p.expect(tkColon)
    let t = parseType(p)
    it.fields.add(Field(name: fldName, typ: t))
    if eat(p, tkComma):
      continue
  let fullyQualifiedName = p.currentInterface & "." & name
  it.typ = p.defineUserType(fullyQualifiedName, declIndex, itemIndex)
  return it

proc parseEnumOrFlags(p: var Parser, name: string, isFlags: bool, docs: string, declIndex: int, itemIndex: int): Item =
  p.importMap[name] = p.currentInterface
  var it = Item(kind: if isFlags: IKFlags else: IKEnum)
  it.name = name
  it.variants = @[]
  it.docs = docs
  p.expect(tkBraceL)
  while true:
    if eat(p, tkBraceR):
      break
    let v = expectIdent(p)
    it.variants.add v
    if eat(p, tkComma):
      continue
  let fullyQualifiedName = p.currentInterface & "." & name
  it.typ = p.defineUserType(fullyQualifiedName, declIndex, itemIndex)
  return it

proc parseUse(p: var Parser): Item =
  let module = expectIdent(p)
  var it = Item(kind: IKUse)
  it.useModule = module
  it.useItems = @[]
  if eat(p, tkPeriod):
    p.expect(tkBraceL)
    while true:
      let nm = expectIdent(p)
      it.useItems.add nm
      p.importMap[nm] = module
      if eat(p, tkComma):
        continue
      elif eat(p, tkBraceR):
        break
      else:
        break
  if eat(p, tkSemicolon):
    discard
  return it

proc parseMethodDecl(p: var Parser, name: string, docs: string): Method =
  var m = Method(name: name, docs: docs, isStatic: false, isConstructor: false, sig: FuncSig(params: @[], result: 0.TypeIdx))
  if name == "constructor":
    m.isConstructor = true
    m.sig = parseFuncSig(p)

  elif eat(p, tkColon):
    if p.tokens.len > 0 and p.current.kind == tkIdent and p.current.text == "static":
      m.isStatic = true
      p.skip()
    if p.tokens.len > 0 and p.current.kind == tkIdent and p.current.text == "func":
      p.skip()
      m.sig = parseFuncSig(p)
    else:
      if p.tokens.len > 0 and p.current.kind == tkParenL:
        m.sig = parseFuncSig(p)
  if eat(p, tkSemicolon):
    discard
  return m

proc parseResource(p: var Parser, name: string, docs: string, declIndex: int, itemIndex: int): Item =
  p.importMap[name] = p.currentInterface
  var it = Item(kind: IKResource)
  it.name = name
  it.methods = @[]
  it.docs = docs
  p.expect(tkBraceL)

  while true:
    if eat(p, tkBraceR):
      break

    let docs = if p.current.kind == tkComment:
      p.current.text
    else:
      ""
    discard p.eat(tkComment)

    let nm = expectIdent(p)
    let m = parseMethodDecl(p, nm, docs)
    it.methods.add m
  let fullyQualifiedName = p.currentInterface & "." & name
  it.typ = p.defineUserType(fullyQualifiedName, declIndex, itemIndex)
  return it

proc parseFuncItem(p: var Parser, name: string, docs: string): Item =
  var it = Item(kind: IKFunc)
  it.name = name
  it.funcSig = FuncSig(params: @[], result: 0.TypeIdx)
  it.docs = docs
  if eat(p, tkColon):
    if p.tokens.len > 0 and p.current.kind == tkIdent and p.current.text == "static":
      p.skip()
    if p.tokens.len > 0 and p.current.kind == tkIdent and p.current.text == "func":
      p.skip()
      it.funcSig = parseFuncSig(p)
  elif p.tokens.len > 0 and p.current.kind == tkIdent and p.current.text == "func":
    p.skip()
    it.funcSig = parseFuncSig(p)
  if eat(p, tkSemicolon):
    discard
  return it

proc parseInterface(p: var Parser, name: string, declIndex: int): Decl =
  p.currentInterface = name
  p.importMap.clear()
  var d = Decl(kind: DKInterface, name: name, body: @[])
  p.expect(tkBraceL)
  var docs = ""
  while true:
    if eat(p, tkBraceR):
      break
    if p.current.kind == tkComment:
      docs = p.current.text
    else:
      docs = ""
    discard p.eat(tkComment)

    if p.current.kind == tkIdent and p.current.text == "record":
      p.skip()
      let nm = expectIdent(p)
      d.body.add parseRecord(p, nm, docs, declIndex, d.body.len)
      continue
    elif p.current.kind == tkIdent and p.current.text == "resource":
      p.skip()
      let nm = expectIdent(p)
      d.body.add parseResource(p, nm, docs, declIndex, d.body.len)
      continue
    elif p.current.kind == tkIdent and (p.current.text == "enum" or p.current.text == "flags"):
      let isFlags = p.current.text == "flags"
      p.skip()
      let nm = expectIdent(p)
      d.body.add parseEnumOrFlags(p, nm, isFlags, docs, declIndex, d.body.len)
      continue
    elif p.current.kind == tkIdent and p.current.text == "use":
      p.skip()
      d.body.add parseUse(p)
      continue
    elif p.current.kind == tkIdent and p.current.text == "import":
      p.skip()
      let nm = expectIdent(p)
      var it = Item(kind: IKImport)
      it.name = nm
      d.body.add it
      if eat(p, tkSemicolon): discard
      continue
    elif p.current.kind == tkIdent:
      let nm = expectIdent(p)
      d.body.add parseFuncItem(p, nm, docs)
      continue
    else:
      p.skip()
  return d

proc parseWorld(p: var Parser, name: string): Decl =
  var d = Decl(kind: DKWorld, name: name, body: @[])
  p.expect(tkBraceL)
  while true:
    if eat(p, tkBraceR):
      break
    if p.tokens.len == 0: break
    if p.current.kind == tkIdent and p.current.text == "use":
      p.skip()
      d.body.add parseUse(p)
      continue
    elif p.current.kind == tkIdent and p.current.text == "import":
      p.skip()
      let nm = expectIdent(p)
      var it = Item(kind: IKImport)
      it.name = nm
      d.body.add it
      if eat(p, tkSemicolon): discard
      continue
    elif p.current.kind == tkIdent and p.current.text == "export":
      p.skip()
      let nm = expectIdent(p)
      var it = Item(kind: IKExport)
      it.name = nm
      d.body.add it
      if eat(p, tkSemicolon): discard
      continue
    else:
      if p.current.kind == tkIdent:
        let nm = expectIdent(p)
        d.body.add parseFuncItem(p, nm, "todo")
        continue
      else:
        p.skip()
  return d

proc parseWitModule*(source: string): WitModule =
  var p = newParser(source)
  p.tokens = lex(source)
  try:
    while p.tokens.len > 0 and p.current.kind != tkEof:
      if p.current.kind == tkIdent and p.current.text == "package":
        p.skip()
        let pkg = expectIdent(p)
        discard p.eat(tkColon)
        let subpkg = expectIdent(p)
        p.module.packageName = pkg & ":" & subpkg
        if eat(p, tkSemicolon):
          discard
        continue
      elif p.current.kind == tkIdent and p.current.text == "interface":
        p.skip()
        let nm = expectIdent(p)
        p.module.decls.add parseInterface(p, nm, p.module.decls.len)
        continue
      elif p.current.kind == tkIdent and p.current.text == "world":
        p.skip()
        let nm = expectIdent(p)
        p.module.decls.add parseWorld(p, nm)
        continue
      else:
        p.skip()
  finally:
    p.tokens.setLen(0)
    p.src = ""

  swap(result, p.module)

proc getWorld*(m: WitModule, name: string): ptr Decl =
  for d in m.decls:
    if d.kind == DKWorld and d.name == name:
      return d.addr
  return nil

proc getInterface*(m: WitModule, name: string): ptr Decl =
  for d in m.decls:
    if d.kind == DKInterface and d.name == name:
      return d.addr
  return nil
