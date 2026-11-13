discard """
  action: "run"
  cmd: "nim $target --undef:useDynlib --nimblePath:./nimbleDir/simplePkgs $options $file"
  timeout: 500
  targets: "c"
"""

import std/[unittest, options, tables, strutils]
import nimsumtree/rope
import text/syntax_map
import treesitter/treesitter
from treesitter/api as ts import nil
import treesitter_json/treesitter_json/json
import misc/[arena, util]
import theme, chroma

type RenderedHighlight = tuple[range: Range[Point], color: Color,
  fontStyle: set[FontStyle], fontScale: float]

proc newFixture(content: string): tuple[syntaxMap: SyntaxMap, query: TSQuery] =
  let language = treeSitterJson()
  let parser = ts.tsParserNew()
  defer: ts.tsParserDelete(parser)
  doAssert ts.tsParserSetLanguage(parser, language)
  let tree = TsTree(impl: ts.tsParserParseString(parser, nil,
    content.cstring, content.len.uint32))
  doAssert not tree.isNil
  const source = "(document) @test"
  var errorOffset: uint32
  var errorType: ts.TSQueryError
  let query = TSQuery(impl: ts.tsQueryNew(language, source.cstring,
    source.len.uint32, errorOffset.addr, errorType.addr))
  doAssert query.impl != nil
  let syntaxMap = newSyntaxMap()
  let highlighter = Highlighter.init(syntaxMap)
  highlighter.snapshot[].rope = Rope.new(content)
  highlighter.snapshot[].layers = @[SyntaxLayer(tree: tree, highlightQuery: query)]
  highlighter.snapshot[].layerIndex = buildLayerIndex(
    highlighter.snapshot[].layers, highlighter.snapshot[].rope)
  (syntaxMap, query)

proc render(syntaxMap: SyntaxMap, cached: bool, start = Point()): seq[RenderedHighlight] =
  let previous = gEnableSyntaxCache
  gEnableSyntaxCache = cached
  defer: gEnableSyntaxCache = previous
  let highlighter = Highlighter.init(syntaxMap)
  let theme = Theme()
  theme.colors["editor.foreground"] = color(1, 1, 1)
  theme.tokenColors["test"] = Style(
    foreground: color(1, 0, 0).some, fontStyle: {Bold}, fontScale: 1.25)
  var arena = initArena()
  var chunks = StyledChunkIterator.init(highlighter.snapshot[].rope,
    arena.addr, highlighter.some, theme)
  chunks.seek(start)
  while chunks.next().getSome(chunk):
    if chunk.len > 0:
      result.add (chunk.point...chunk.endPoint, chunk.color,
        chunk.fontStyle, chunk.fontScale)

suite "Syntax highlight cache":
  test "cold and warm cache match uncached styling across leaves":
    let (syntaxMap, query) = newFixture("[\n" & "1,\n".repeat(200) & "2\n]")
    defer: query.deinit()
    let expected = syntaxMap.render(cached = false)
    check expected.len > 200
    for chunk in expected:
      check chunk.color == color(1, 0, 0)
      check chunk.fontStyle == {Bold}
      check chunk.fontScale == 1.25
    check syntaxMap.render(cached = true) == expected
    check syntaxMap.render(cached = true) == expected

  test "first render after edits matches uncached styling before reparsing":
    var content = "[\n" & "1,\n".repeat(200) & "2\n]"
    let (syntaxMap, query) = newFixture(content)
    defer: query.deinit()
    discard syntaxMap.render(cached = true)
    for i in 1..3:
      content.insert("1", 2)
      syntaxMap.addEdit(TSInputEdit(
        startIndex: 2, oldEndIndex: 2, newEndIndex: 3,
        startPosition: tsPoint(1, 0), oldEndPosition: tsPoint(1, 0),
        newEndPosition: tsPoint(1, 1)), Rope.new(content))
      syntaxMap.applyEdits()
      let expected = syntaxMap.render(cached = false)
      check syntaxMap.render(cached = true) == expected
      check syntaxMap.render(cached = true) == expected

  test "cold cache after seeking inside a leaf matches uncached styling":
    let (syntaxMap, query) = newFixture("[\n" & "1,\n".repeat(200) & "2\n]")
    defer: query.deinit()
    let start = Point(row: 5, column: 0)
    let expected = syntaxMap.render(cached = false, start = start)
    check syntaxMap.render(cached = true, start = start) == expected
    check syntaxMap.render(cached = true, start = start) == expected
