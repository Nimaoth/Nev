import std/[strutils, sequtils, os, tables, options, unicode]
import npeg
import npeg/codegen
import scripting_api
import regex
import misc/custom_logger

logCategory "snippet"

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

proc offset*(data: var SnippetData, selection: Selection) =
  for tabStops in data.tabStops.mvalues:
    for tabStop in tabStops.mitems:
      let uiae = tabStop
      tabStop.first = tabStop.first.add(selection)
      tabStop.last = tabStop.last.add(selection)

proc updateSnippetData(data: var SnippetData, tokens: openArray[Token], variables: Table[string, string]) =
  for token in tokens:
    case token.kind:
    of Text:
      data.text.add token.text
      data.location.column += token.text.len

    of Nested:
      data.highestTabStop = max(data.highestTabStop, token.tabStopIndex)
      let first = data.location
      data.updateSnippetData(token.tokens, variables)
      let last = data.location
      data.tabStops.mgetOrPut(token.tabStopIndex, @[]).add (first, last)

    of Variable:
      if token.regex.isSome:
        let value = variables.getOrDefault(token.name, "")
        let regex = re2 token.regex.get
        var match: RegexMatch2

        let matched = value.find(regex, match)

        for format in token.tokens:

          case format.kind
          of Text:
            data.text.add format.text
            data.location.column += format.text.len

          of Format:
            let capturedBounds = if format.tabStopIndex == 0:
              match.boundaries
            elif format.tabStopIndex <= match.captures.len:
              match.captures[format.tabStopIndex - 1]
            else:
              0..<0

            let capturedValue = case format.transformation
            of "":
              if matched:
                value[capturedBounds]
              else:
                value
            of "/":
              assert format.tokens.len == 1 and format.tokens[0].kind == Text
              if matched:
                case format.tokens[0].text
                of "upcase":
                  value[capturedBounds].toUpper
                of "downcase":
                  value[capturedBounds].toLower
                of "capitalize":
                  value[capturedBounds].capitalize
                else:
                  assert false
                  value
              else:
                value

            of "+":
              assert format.tokens.len == 1 and format.tokens[0].kind == Text
              if matched:
                format.tokens[0].text
              else:
                value

            of "-":
              assert format.tokens.len == 1 and format.tokens[0].kind == Text
              if matched:
                value
              else:
                format.tokens[0].text

            of "?":
              assert format.tokens.len == 2 and format.tokens[0].kind == Text and format.tokens[1].kind == Text
              if matched:
                format.tokens[0].text
              else:
                format.tokens[1].text

            else:
              assert false
              value

            data.text.add capturedValue
            data.location.column += capturedValue.len
          else:
            assert false

      elif token.name in variables:
        let value = variables[token.name]
        data.text.add value
        data.location.column += value.len

      else:
        data.updateSnippetData(token.tokens, variables)

    of Choice:
      data.text.add token.tokens[0].text
      data.location.column += token.tokens[0].text.len

    of Format:
      discard

proc createSnippetData*(snippet: Snippet, location: Cursor, variables: Table[string, string], indent = int.none): SnippetData =
  result = SnippetData(location: location, indent: indent.get(0))
  result.updateSnippetData(snippet.tokens, variables)
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

  pattern <- tabstop | variable

  nestedPattern <- pushStack * *(escaped | (unescaped - {'}', '$'}) | pattern)

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

  choice <- "${" * >number * '|' * (pushStack * choiceText) * *(comma * choiceText) * "|}":
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
  proc testString(str: string, expected: string, expectedData: string = "", print = false) =
    let variables = toTable {
      "TM_FILENAME": "test.TXT",
      "TM_FILENAME_BASE": "test",
      "TM_FILETPATH": "foo/bar/test.TXT",
      "TM_DIRECTORY": "foo/bar",
      "TM_LINE_INDEX": "5",
      "TM_LINE_NUMBER": "6",
      "TM_CURRENT_LINE": "hello world!",
      "TM_CURRENT_WORD": "world",
      "TM_SELECTED_TEXT": "orl",
    }

    if print:
      echo "test: ", str, "   ->   ", expected
    var state = Snippet()
    let res = snippetParser.match(str, state)
    if print: echo fmt"ok: {res.ok}, len: {res.matchLen}, max: {res.matchMax}"
    let snippetData = state.createSnippetData((0, 0), variables)
    let finalResult = state.tokens.join(" ")
    if print:
      echo finalResult

    if finalResult != expected:
      echo "-------- FAILED: ", str
      echo "expected: ", expected
      echo "     got: ", finalResult

    if $snippetData.text != expectedData:
      echo "-------- FAILED: ", str
      echo "expected: ", expectedData
      echo "     got: ", $snippetData.text

    if print: echo "---------------------"

  proc testAll() =
    echo "test all snippets"
    defer:
      echo "test all snippets done"

    testString(
      r"abc",
      r"'abc'",
      r"abc")
    testString(
      r"a\$c",
      r"'a$c'",
      r"a$c")
    testString(
      r"$a",
      r"@a()",
      r"")
    testString(
      r"${a}",
      r"@a()",
      r"")
    testString(
      r"${x:abc\$\\\}def}",
      r"@x('abc$\}def')",
      r"abc$\}def")
    testString(
      r"$0abc($1)",
      r"$0() 'abc(' $1() ')'",
      r"abc()")
    testString(
      r"abc(${1:xyz})",
      r"'abc(' $1('xyz') ')'",
      r"abc(xyz)")
    testString(
      r"${1:abc\$\\\}def}",
      r"$1('abc$\}def')",
      r"abc$\}def")
    testString(
      r"foo ${a:abc$1def} bar",
      r"'foo ' @a('abc' $1() 'def') ' bar'",
      r"foo abcdef bar")
    testString(
      r"${1|abc,def|}",
      r"$1('abc' | 'def')",
      r"abc")
    testString(
      r"${1|abc\,\$,\|def|}",
      r"$1('abc,$' | '|def')",
      r"abc,$")
    testString(
      r"${TM_FILENAME/(.*)/$1/}",
      r"@TM_FILENAME[ (.*) / &1() /  ]",
      r"test.TXT")
    testString(
      r"${TM_FILENAME/(.*)/${1}/}",
      r"@TM_FILENAME[ (.*) / &1() /  ]",
      r"test.TXT")
    testString(
      r"${TM_FILENAME/(.*)/${1:/upcase}/}",
      r"@TM_FILENAME[ (.*) / &1(/'upcase') /  ]",
      r"TEST.TXT")
    testString(
      r"${TM_FILENAME/(.*)/${1:/downcase}/}",
      r"@TM_FILENAME[ (.*) / &1(/'downcase') /  ]",
      r"test.txt")
    testString(
      r"${TM_FILENAME/(.*)/${1:/capitalize}/}",
      r"@TM_FILENAME[ (.*) / &1(/'capitalize') /  ]",
      r"Test.TXT")
    testString(
      r"${TM_FILENAME/(.*)/${1:+yes}/}",
      r"@TM_FILENAME[ (.*) / &1(+'yes') /  ]",
      r"yes")
    testString(
      r"${TM_FILENAME/abc/${1:+yes}/}",
      r"@TM_FILENAME[ abc / &1(+'yes') /  ]",
      r"test.TXT")
    testString(
      r"${TM_FILENAME/(.*)/${1:-no}/}",
      r"@TM_FILENAME[ (.*) / &1(-'no') /  ]",
      r"test.TXT")
    testString(
      r"${TM_FILENAME/abc/${1:-no}/}",
      r"@TM_FILENAME[ abc / &1(-'no') /  ]",
      r"no")
    testString(
      r"${TM_FILENAME/(.*)/${1:?yes:no}/}",
      r"@TM_FILENAME[ (.*) / &1(?'yes' | 'no') /  ]",
      r"yes")
    testString(
      r"${TM_FILENAME/abc/${1:?yes:no}/}",
      r"@TM_FILENAME[ abc / &1(?'yes' | 'no') /  ]",
      r"no")
    testString(
      r"${TM_FILENAME/(.*)/${1:no}/}",
      r"@TM_FILENAME[ (.*) / &1(-'no') /  ]",
      r"test.TXT")
    testString(
      r"${TM_FILENAME/abc/${1:no}/}",
      r"@TM_FILENAME[ abc / &1(-'no') /  ]",
      r"no")
    testString(
      r"${TM_FILENAME/(.*)\..+$/$1/}",
      r"@TM_FILENAME[ (.*)\..+$ / &1() /  ]",
      r"test")
    testString(
      r"${a/(.*)\/(.*)/$2\\$1/}",
      r"@a[ (.*)\/(.*) / &2() '\' &1() /  ]",
      r"\")
    testString(
      r"${a/(.*)\/(.*)/+-${1:/upcase}-+/gI}",
      r"@a[ (.*)\/(.*) / '+-' &1(/'upcase') '-+' / gI ]",
      r"+--+")
    testString(
      r"${TM_DIRECTORY/(.*)\/(.*)/${1:/capitalize}\\${2:/upcase}/}",
      r"@TM_DIRECTORY[ (.*)\/(.*) / &1(/'capitalize') '\' &2(/'upcase') /  ]",
      r"Foo\BAR")
    testString(
      r"${TM_DIRECTORY/(.*)\/(.*)/${1:/capitalize}\\${3:/upcase}/}",
      r"@TM_DIRECTORY[ (.*)\/(.*) / &1(/'capitalize') '\' &3(/'upcase') /  ]",
      r"Foo\")
    testString(
      r"${TM_DIRECTORY/(.*)\\(.*)/${1:/capitalize}\\${2:/upcase}/}",
      r"@TM_DIRECTORY[ (.*)\\(.*) / &1(/'capitalize') '\' &2(/'upcase') /  ]",
      r"foo/bar\foo/bar")
    testString(
      r"""log lvl${1:Info} &"[${TM_FILENAME/(.*)/${1:/upcase}/}] $2" """,
      r"@TM_DIRECTORY[ (.*)\\(.*) / &1(/'capitalize') '\' &2(/'upcase') /  ]",
      r"""log lvlInfo &"[TEST.TXT] " """)

  static:
    testAll()

  testAll()
