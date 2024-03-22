## Originally from https://github.com/pigmej/fuzzy
#[
MIT License

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is furnished
to do so, subject to the following conditions:

The above copyright notice and this permission notice (including the next
paragraph) shall be included in all copies or substantial portions of the
Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS
OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF
OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

]#

import std/[os, strutils]
from algorithm import sorted
# from std/editdistance import editDistanceAscii  # stdlib one yields correct distance BUT for ratio cost should be higher because yields better results (Python does that too)

var distance: seq[int]
proc levenshtein_ratio_and_distance*(s, t: string, ratio_calc = true, caseInsensitive: static bool = true): float =
  ## This should be very similar to python implementation
  ## Calculates ratio and distance depending on `ratio_calc`
  let rows = s.len + 1
  let cols = t.len + 1
  var cost: int
  distance.setLen(rows * cols)
  for i in 1 ..< rows:
    for k in 1 ..< cols:
      distance[i * cols] = i
      distance[k] = k

  for col in 1 ..< cols:
    for row in 1 ..< rows:
      let same = when caseInsensitive:
        s[row - 1].toLowerAscii == t[col - 1].toLowerAscii
      else:
        s[row - 1] == t[col - 1]

      if same:
        cost = 0
      else:
        if ratio_calc:
          cost = 2
        else:
          cost = 1
      distance[col + row * cols] = min(min(distance[col + (row - 1) * cols] + 1, distance[(col - 1) + row * cols] + 1), distance[(col - 1) + (row - 1) * cols] + cost)
  let dst = distance[distance.high]
  if ratio_calc:
    # echo s, " - ", t, " = ", $(((s.len + t.len) - dst).float / (s.len + t.len).float)
    return ((s.len + t.len) - dst).float / (s.len + t.len).float
  else:
    return dst.float

proc fuzzyMatch*(s1, s2: string, caseInsensitive: static bool = true): float =
  ## Just basic fuzzy match
  ## Could be used as a base for other algorithms
  if s1.len > s2.len:
    return levenshtein_ratio_and_distance(s2, s1, ratio_calc = true, caseInsensitive = caseInsensitive)
  return levenshtein_ratio_and_distance(s2, s1, ratio_calc = true, caseInsensitive = caseInsensitive)

proc fuzzyMatchSmart*(s1, s2: string, withSubstring = true): float =
  ##Tries to be smart about the strings so:
  ## - lowercase
  ## - sorts substrings
  ## - best matching substring of length of shorter one
  var str1 = s1
  var str2 = s2
  str1 = str1.split(" ").sorted().join(" ")
  str2 = str2.split(" ").sorted().join(" ")
  if str1 == str2:
    return 1.0
  if str1.len == str2.len:
    return fuzzyMatch(str1, str2, caseInsensitive = true)
  var shorter, longer: string
  if str1.len < str2.len:
    shorter = str1
    longer = str2
  else:
    shorter = str2
    longer = str1
  var tmpRes = fuzzyMatch(shorter, longer, caseInsensitive = true)
  if withSubstring:
    let lengthDiff = longer.len - shorter.len
    var subMatch: float
    for i in 0 .. lengthDiff:
      subMatch = fuzzyMatch(shorter, longer[i ..< i + shorter.len], caseInsensitive = true)
      tmpRes = max(tmpRes, subMatch)
  return tmpRes

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

proc matchFuzzySimple*(a: string, b: string): float =
  return fuzzyMatch(a, b, caseInsensitive = true)