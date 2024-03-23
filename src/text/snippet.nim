import std/[strutils, sequtils, strformat, os, tables, options]
import npeg
import npeg/codegen
import scripting_api

type
  TokenKind* = enum Text, Nested, Variable, Choice
  Token* = object
    tabStopIndex: int = -1
    tokens: seq[Token]

    case kind: TokenKind
    of Text:
      text: string
    of Nested, Choice:
      discard
    of Variable:
      name: string

  Snippet* = object
    tokens*: seq[Token]

    stack: seq[seq[Token]]
    varName: string

type SnippetData* = object
  currentTabStop*: int = 0
  highestTabStop*: int = 0
  tabStops*: Table[int, Selections]
  text*: string
  indent: int
  location: Cursor

proc updateSnippetData(data: var SnippetData, tokens: openArray[Token]) =
  for token in tokens:
    case token.kind:
    of Text:
      data.text.add token.text
      data.location.column += token.text.len

    of Nested:
      data.highestTabStop = max(data.highestTabStop, token.tabStopIndex)
      let first = data.location
      data.updateSnippetData(token.tokens)
      let last = data.location
      data.tabStops.mgetOrPut(token.tabStopIndex, @[]).add (first, last)

    of Variable:
      data.text.add token.name
      data.location.column += token.name.len
      data.updateSnippetData(token.tokens)

    of Choice:
      data.text.add token.tokens[0].text
      data.location.column += token.tokens[0].text.len

proc createSnippetData*(snippet: Snippet, location: Cursor, indent = int.none): SnippetData =
  result = SnippetData(location: location, indent: indent.get(0))
  result.updateSnippetData(snippet.tokens)
  if 0 notin result.tabStops:
    result.tabStops[0] = @[result.location.toSelection]

template last[T](s: seq[T]): lent T = s[s.high]
proc popEmptyLast(self: var Snippet) =
  if self.tokens.len == 0:
    return
  if self.tokens.last.kind != Nested:
    return
  if self.tokens.last.tabStopIndex != -1:
    return
  if self.tokens.last.tokens.len != 0:
    return
  self.tokens.setLen(self.tokens.high)

func `$`*(t: Token): string =
  case t.kind
  of Text:
    return "'" & t.text & "'"
  of Nested:
    return "$" & $t.tabStopIndex & "(" & t.tokens.join(" ") & ")"
  of Variable:
    return "@" & $t.name & "(" & t.tokens.join(" ") & ")"
  of Choice:
    return "$" & $t.tabStopIndex & "(" & t.tokens.join(" | ") & ")"

let snippetParser = peg("snippet", state: Snippet):
  ## LSP snippet parser
  ## See https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#snippet_syntax

  snippet <- *(escaped | (unescaped - '$') | pattern) * snippetEnd

  snippetEnd <- !1:
    state.popEmptyLast()

  escaped <- '\\' * >1:
    if state.tokens.len == 0 or state.tokens[state.tokens.high].kind != Text:
      state.tokens.add Token(kind: Text, text: $1)
    else:
      state.tokens[state.tokens.high].text.add $1

  unescaped <- >1:
    if state.tokens.len == 0 or state.tokens[state.tokens.high].kind != Text:
      state.tokens.add Token(kind: Text, text: $1)
    else:
      state.tokens[state.tokens.high].text.add $1

  prePattern <- 0:
    state.stack.add move state.tokens

  pattern <- tabstop | variable

  nestedPattern <- prePattern * *(escaped | (unescaped - {'}', '$'}) | pattern)

  variable <- variable1 | variable2 # | variable3

  variable1 <- '$' * varName | "${" * varName * '}':
    state.tokens.add Token(kind: Variable, name: state.varName)

  variable2 <- "${" * >varName * ':' * nestedPattern * '}':
    var token = Token(kind: Variable, name: $1, tokens: move state.tokens)
    state.tokens = state.stack.pop
    state.tokens.add token

  # variable3 <- "${" * >varName * '/' * >regex * '/' * '}': # todo
  #   var token = Token(kind: Variable, name: $1, tokens: move state.tokens)
  #   state.tokens = state.stack.pop
  #   state.tokens.add token

  tabstop <- tabstop1 | tabstop2 | choice

  tabstop1 <- '$' * >number | "${" * >number * '}':
    state.tokens.add Token(kind: Nested, tabStopIndex: parseInt($1))

  tabstop2 <- "${" * >number * ':' * nestedPattern * '}':
    var token = Token(kind: Nested, tabStopIndex: parseInt($1), tokens: move state.tokens)
    state.tokens = state.stack.pop
    state.tokens.add token

  choiceText <- *(escaped | (unescaped - {'|', ','}))

  comma <- ',':
    state.tokens.add Token(kind: Text)

  preChoice <- 0:
    state.stack.add move(state.tokens)

  choice <- "${" * >number * '|' * preChoice * choiceText * *(comma * choiceText) * "|}":
    var token = Token(kind: Choice, tabStopIndex: parseInt($1), tokens: move state.tokens)
    state.tokens = state.stack.pop
    state.tokens.add token

  number <- +{'0'..'9'}
  varName <- >({'_', 'a'..'z', 'A'..'Z'} * *{'_', 'a'..'z', 'A'..'Z', '0'..'9'}):
    state.varName = $1

  text <- *1

proc parseSnippet*(input: string): Option[Snippet] =
  var snippet = Snippet()
  let res = snippetParser.match(input, snippet)
  if res.ok:
    return snippet.some
  return Snippet.none

when isMainModule:
  proc testString(str: string, expected: string) =
    echo "test: ", str, "   ->   ", expected
    var state = Snippet()
    let res = snippetParser.match(str, state)
    echo fmt"ok: {res.ok}, len: {res.matchLen}, max: {res.matchMax}"
    let finalResult = state.tokens.join(" ")
    echo finalResult
    echo state.createSnippetData()
    echo "---------------------"

    assert finalResult == expected

  # testString r"abc", "'abc'"
  # testString r"a\$c", "'a$c'"
  # testString r"$a", "@a()"
  # testString r"${a}", "@a()"
  # testString r"${a:abc\$\\\}def}", r"@a('abc$\}def')"
  testString r"$0abc($1)", "'abc(' $1() ')'"
  testString r"abc(${1:xyz})", "'abc(' $1('xyz') ')'"
  testString r"${1:abc\$\\\}def}", r"$1('abc$\}def')"
  # testString r"foo ${a:abc$1def} bar", "'foo ' @a('abc' $1() 'def') ' bar'"
  # testString r"${1|abc,def|}", "$1('abc' | 'def')"
  # testString r"${1|abc\,\$,\|def|}", r"$1('abc,$' | '|def')"
