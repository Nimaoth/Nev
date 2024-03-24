import std/[strutils, sequtils, strformat, os, tables, options]
import npeg
import npeg/codegen
import scripting_api

type
  TokenKind* = enum Text, Nested, Variable, Choice, Format
  Token* = object
    tabStopIndex: int = -1
    tokens: seq[Token]

    case kind: TokenKind
    of Nested, Choice:
      discard

    of Text:
      text: string

    of Variable:
      name: string
      regex: Option[string]
      regexOptions: string

    of Format:
      transformation: string

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

    of Format:
      discard

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
    if t.regex.isSome:
      return "@" & $t.name & "[ " & t.regex.get & " / " & t.tokens.join(" ") & " / " & t.regexOptions & " ]"
    return "@" & $t.name & "(" & t.tokens.join(" ") & ")"
  of Choice:
    return "$" & $t.tabStopIndex & "(" & t.tokens.join(" | ") & ")"
  of Format:
    return "&" & $t.tabStopIndex & "(" & t.transformation & t.tokens.join(" | ") & ")"

# LSP snippet parser
# See https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#snippet_syntax
const snippetParser = peg("snippet", state: Snippet):

  snippet <- *(escaped | (unescaped - '$') | pattern) * snippetEnd

  number <- +{'0'..'9'}
  varName <- >({'_', 'a'..'z', 'A'..'Z'} * *{'_', 'a'..'z', 'A'..'Z', '0'..'9'}):
    state.varName = $1

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

  escapedRaw <- '\\' * 1
  unescapedRaw <- 1

  pushStack <- 0:
    state.stack.add state.tokens
    state.tokens.setLen 0

  prePattern <- 0:
    state.stack.add state.tokens
    state.tokens.setLen 0

  pattern <- tabstop | variable

  nestedPattern <- prePattern * *(escaped | (unescaped - {'}', '$'}) | pattern)

  variable <- variable1 | variable2 | variable3
  variable1 <- '$' * varName | "${" * varName * '}':
    state.tokens.add Token(kind: Variable, name: state.varName)
  variable2 <- "${" * >varName * ':' * nestedPattern * '}':
    var token = Token(kind: Variable, name: $1, tokens: state.tokens)
    state.tokens.setLen 0
    state.tokens = state.stack.pop
    state.tokens.add token

  options <- *Alpha
  regex <- *(('\\' * 1) | (1 - {'/'}))
  variable3 <- "${" * >varName * '/' * >regex * '/' * (pushStack * formatOrText) * '/' * >options * '}':
    var token = Token(kind: Variable, name: $1, regex: some $2, regexOptions: $3, tokens: state.tokens)
    state.tokens.setLen 0
    state.tokens = state.stack.pop
    state.tokens.add token

  formatOrText <- *(escaped | (unescaped - {'$', '/'}) | format) # fills existing state.tokens

  format <- format1 | format2 | format3 | format4 | format5 | format6
  format1 <- '$' * >number | "${" * >number * '}':
    state.tokens.add Token(kind: Format, tabStopIndex: parseInt($1))
  format2 <- "${" * >number * ":/" * >("upcase" | "downcase" | "capitalize") * '}':
    state.tokens.add Token(kind: Format, tabStopIndex: parseInt($1), transformation: "/", tokens: @[Token(kind: Text, text: $2)])
  format3 <- "${" * >number * ":+" * > *(escapedRaw | (unescapedRaw - '}')) * '}':
    state.tokens.add Token(kind: Format, tabStopIndex: parseInt($1), transformation: "+", tokens: @[Token(kind: Text, text: $2)])
  format4 <- "${" * >number * ":-" * > *(escapedRaw | (unescapedRaw - '}')) * '}':
    state.tokens.add Token(kind: Format, tabStopIndex: parseInt($1), transformation: "-", tokens: @[Token(kind: Text, text: $2)])
  format5 <- "${" * >number * ":?" * >*(escapedRaw | (unescapedRaw - {':', '}'})) * ':' * >*(escapedRaw | (unescapedRaw - {'}'})) * '}':
    state.tokens.add Token(kind: Format, tabStopIndex: parseInt($1), transformation: "?", tokens: @[Token(kind: Text, text: $2), Token(kind: Text, text: $3)])
  format6 <- "${" * >number * ":" * > *(escapedRaw | (unescapedRaw - '}')) * '}':
    state.tokens.add Token(kind: Format, tabStopIndex: parseInt($1), transformation: "-", tokens: @[Token(kind: Text, text: $2)])

  formatTransformation <- formatTransformation1
  formatTransformation1 <- "/upcase" | "/downcase" | "/capitalize"

  tabstop <- tabstop1 | tabstop2 | choice
  tabstop1 <- '$' * >number | "${" * >number * '}':
    state.tokens.add Token(kind: Nested, tabStopIndex: parseInt($1))
  tabstop2 <- "${" * >number * ':' * nestedPattern * '}':
    var token = Token(kind: Nested, tabStopIndex: parseInt($1), tokens: state.tokens)
    state.tokens.setLen 0
    state.tokens = state.stack.pop
    state.tokens.add token

  choiceText <- *(escaped | (unescaped - {'|', ','}))

  comma <- ',':
    state.tokens.add Token(kind: Text)

  preChoice <- 0:
    state.stack.add state.tokens
    state.tokens.setLen 0

  choice <- "${" * >number * '|' * preChoice * choiceText * *(comma * choiceText) * "|}":
    var token = Token(kind: Choice, tabStopIndex: parseInt($1), tokens: state.tokens)
    state.tokens.setLen 0
    state.tokens = state.stack.pop
    state.tokens.add token

proc parseSnippet*(input: string): Option[Snippet] =
  var snippet = Snippet()
  let res = snippetParser.match(input, snippet)
  if res.ok:
    return snippet.some
  return Snippet.none

when isMainModule:
  proc testString(str: string, expected: string, print = false) =
    if print:
      echo "test: ", str, "   ->   ", expected
    var state = Snippet()
    let res = snippetParser.match(str, state)
    if print: echo fmt"ok: {res.ok}, len: {res.matchLen}, max: {res.matchMax}"
    let finalResult = state.tokens.join(" ")
    if print:
      echo finalResult
      echo state.createSnippetData((0, 0))

    if finalResult != expected:
      echo "-------- FAILED: ", str
      echo "expected: ", expected
      echo "     got: ", finalResult

    if print: echo "---------------------"

  proc testAll() =
    testString r"abc", "'abc'"
    testString r"a\$c", "'a$c'"
    testString r"$a", "@a()"
    testString r"${a}", "@a()"
    testString r"${a:abc\$\\\}def}", r"@a('abc$\}def')"
    testString r"$0abc($1)", "$0() 'abc(' $1() ')'"
    testString r"abc(${1:xyz})", "'abc(' $1('xyz') ')'"
    testString r"${1:abc\$\\\}def}", r"$1('abc$\}def')"
    testString r"foo ${a:abc$1def} bar", "'foo ' @a('abc' $1() 'def') ' bar'"
    testString r"${1|abc,def|}", "$1('abc' | 'def')"
    testString r"${1|abc\,\$,\|def|}", r"$1('abc,$' | '|def')"
    testString r"${TM_FILENAME/.*/$1/}", r"@TM_FILENAME[ .* / &1() /  ]"
    testString r"${TM_FILENAME/.*/${1}/}", r"@TM_FILENAME[ .* / &1() /  ]"
    testString r"${TM_FILENAME/.*/${1:/upcase}/}", r"@TM_FILENAME[ .* / &1(/'upcase') /  ]"
    testString r"${TM_FILENAME/.*/${1:+yes}/}", r"@TM_FILENAME[ .* / &1(+'yes') /  ]"
    testString r"${TM_FILENAME/.*/${1:-no}/}", r"@TM_FILENAME[ .* / &1(-'no') /  ]"
    testString r"${TM_FILENAME/.*/${1:?yes:no}/}", r"@TM_FILENAME[ .* / &1(?'yes' | 'no') /  ]"
    testString r"${TM_FILENAME/.*/${1:no}/}", r"@TM_FILENAME[ .* / &1(-'no') /  ]"
    testString r"${TM_FILENAME/(.*)\..+$/$1/gI}", r"@TM_FILENAME[ (.*)\..+$ / &1() / gI ]"
    testString r"${TM_SELECTED_TEXT/(.*)\/(.*)/$2\\$1/}", r"@TM_SELECTED_TEXT[ (.*)\/(.*) / &2() '\' &1() /  ]"
    testString r"${TM_SELECTED_TEXT/(.*)\/(.*)/+-${1:/upcase}-+/gI}", r"@TM_SELECTED_TEXT[ (.*)\/(.*) / '+-' &1(/'upcase') '-+' / gI ]"

  static:
    testAll()

  testAll()