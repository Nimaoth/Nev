import std/[strutils, unicode, os, strformat, options, tables, algorithm, sequtils]
import regex

let repos = [
  "tree-sitter/tree-sitter-scala",
  "tree-sitter/tree-sitter-regex",
  "tree-sitter/tree-sitter-ocaml/grammars/interface",
  "tree-sitter/tree-sitter-ocaml/grammars/ocaml",
  "tree-sitter/tree-sitter-ocaml/grammars/type",
  "tree-sitter/tree-sitter-python",
  "tree-sitter/tree-sitter-c-sharp",
  "tree-sitter/tree-sitter-json",
  "tree-sitter/tree-sitter-javascript",
  "tree-sitter/tree-sitter-typescript/typescript",
  "tree-sitter/tree-sitter-typescript/tsx",
  "tree-sitter/tree-sitter-php/php",
  "tree-sitter/tree-sitter-php/php_only",
  "tree-sitter/tree-sitter-java",
  "tree-sitter/tree-sitter-ruby",
  "tree-sitter/tree-sitter-cpp",
  "tree-sitter/tree-sitter-c",
  "tree-sitter/tree-sitter-jsdoc",
  "tree-sitter/tree-sitter-go",
  "tree-sitter/tree-sitter-ql",
  "tree-sitter/tree-sitter-bash",
  "tree-sitter/tree-sitter-rust",
  "tree-sitter/tree-sitter-css",
  "tree-sitter/tree-sitter-haskell",
  "tree-sitter/tree-sitter-html",
  "tree-sitter/tree-sitter-agda",
  "tree-sitter-grammars/tree-sitter-query",
  "tree-sitter/tree-sitter-toml",
  "tree-sitter-grammars/tree-sitter-toml",
  "alex-pinkus/tree-sitter-swift",
]

proc findHighlightQuery(dir: string): Option[string] =
  for (kind, path) in walkDir(dir, relative=false):
    case kind
    of pcFile:
      if path.endsWith "highlights.scm":
        return path.some

    of pcDir:
      let res = findHighlightQuery(path)
      if res.isSome:
        return res
    else:
      discard

let captureRegex = re2"@[\w\.]+"

var captures: Table[string, Table[string, int]]

for repo in repos:
  let i = repo.find("/")
  if i == -1:
    continue

  let a = true

  let nameAndPath = repo[i+1..^1]

  let fullName = if (let k = nameAndPath.find("/"); k != -1):
    nameAndPath[0..<k]
  else:
    nameAndPath

  let name = fullName.replace("tree-sitter-", "")

  let path = "languages/" & fullName & "/queries"

  echo &"Collect highlight captures from {path}"
  let highlightQuery = findHighlightQuery(path)
  if highlightQuery.isSome:

    let content = readFile(highlightQuery.get)
    mkDir(&"languages/{name}/queries")
    # writeFile(&"languages/{name}/queries/highlights.scm", content)
    cpFile(highlightQuery.get, &"languages/{name}/queries/highlights.scm")

    # echo content[0..min(50, content.high)]
    for match in content.findAll(captureRegex):
      let text = content[match.boundaries]
      # echo "  ", text, ": ", match

      captures.mgetOrPut(text, initTable[string, int]()).mgetOrPut(path, 0).inc

echo ""

var captureNames: seq[string] = @[]
for (capture, files) in captures.pairs:
  captureNames.add capture

echo ""

captureNames.sort()
echo captureNames.mapIt(it[1..^1]).join("\n")

echo ""

for capture in captureNames:
  echo capture, ": ", captures[capture].len, " files"