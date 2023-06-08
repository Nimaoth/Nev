import std/[os, strutils]
import fuzzy

proc matchPath*(path: string, pattern: string): float =
  let path = path.toLower
  let pattern = pattern.toLower

  # echo "matchPath ", path, " with ", pattern

  var (folder, name, ext) = path.splitFile
  var (patternFolder, patternName, patternExt) = pattern.splitFile

  if ext.len == 0 and name.startsWith("."):
    ext = name
    name = ""

  if patternExt.len == 0 and patternName.startsWith("."):
    patternExt = patternName
    patternName = ""

  if patternFolder.len > 0 and folder.len > 0:
    let folders = folder.split('/')
    let subPatterns = patternFolder.split('/')

    for p in subPatterns:
      var highest = 0.0
      for f in folders:
        let score = fuzzyMatch(p, f)
        # echo "  matchfolder ", p, " with ", f, " -> ", score
        highest = max(highest, score)
      result += highest


  if patternName.len > 0 and name.len > 0:
    result += fuzzyMatch(patternName, name)
    # echo "  match ", patternName, " with ", name, " -> ", result

  if patternExt.len > 0 and ext.len > 0:
    result += fuzzyMatch(patternExt, ext)
    # echo "  match ", patternExt, " with ", ext, " -> ", result

proc matchFuzzy*(a: string, b: string): float =
  return fuzzyMatchSmart(a, b)