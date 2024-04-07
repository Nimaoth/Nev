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

const
  MaxUnmatchedLeadingChar = 3
  ## Maximum number of times the penalty for unmatched leading chars is applied.

type
  ScoreCard* = enum
    StartMatch          ## Start matching.
    LeadingCharDiff     ## An unmatched, leading character was found.
    CharDiff            ## An unmatched character was found.
    CharMatch           ## A matched character was found.
    ConsecutiveMatch    ## A consecutive match was found.
    LeadingCharMatch    ## The character matches the beginning of the
                        ## string or the first character of a word
                        ## or camel case boundary.
    WordBoundryMatch    ## The last ConsecutiveCharMatch that
                        ## immediately precedes the end of the string,
                        ## end of the pattern, or a LeadingCharMatch.

    PatternOversize     ## The pattern is longer than the string.

  FuzzyMatchConfig* = object
    stateScores: array[ScoreCard, int] = [
      StartMatch:       -100,
      LeadingCharDiff:  -3,
      CharDiff:         -1,
      CharMatch:        0,
      ConsecutiveMatch: 5,
      LeadingCharMatch: 10,
      WordBoundryMatch: 20,
      PatternOversize:  -3,
    ]
    ignoredChars: set[char] = {'_', ' ', '.'}
    maxRecursionLevel: int = 4

const defaultPathMatchingConfig* = FuzzyMatchConfig(ignoredChars: {' '})
const defaultCompletionMatchingConfig* = FuzzyMatchConfig(ignoredChars: {' '})

proc matchFuzzySublime*(pattern, str: openArray[char], matches: var seq[int], recordMatches: bool, config: FuzzyMatchConfig = FuzzyMatchConfig(), recursionLevel: int = 0, baseIndex: int = 0): tuple[score: int, matched: bool]
proc matchFuzzySublime*(pattern, str: string, config: FuzzyMatchConfig = FuzzyMatchConfig()): tuple[score: int, matched: bool] =
  var matches: seq[int]
  matchFuzzySublime(pattern.toOpenArray(0, pattern.high), str.toOpenArray(0, str.high), matches, false, config)

proc matchFuzzySublime*(pattern, str: openArray[char], matches: var seq[int], recordMatches: bool, config: FuzzyMatchConfig = FuzzyMatchConfig(), recursionLevel: int = 0, baseIndex: int = 0): tuple[score: int, matched: bool] =
  var
    scoreState = StartMatch
    unmatchedLeadingCharCount = 0
    consecutiveMatchCount = 0
    strIndex = 0
    patIndex = 0
    score = 0

  if recursionLevel > config.maxRecursionLevel:
    return (score: int.low, matched: false)

  if pattern.len > str.len:
    score += config.stateScores[PatternOversize] * (pattern.len - str.len)

  template transition(nextState) =
    scoreState = nextState
    score += config.stateScores[scoreState]

  var bestRecursionMatches: seq[int]
  var bestRecursionScore = int.low

  while (strIndex < str.len) and (patIndex < pattern.len):
    var
      patternChar = pattern[patIndex].toLowerAscii
      strChar     = str[strIndex].toLowerAscii

    # Ignore certain characters
    if patternChar in config.ignoredChars:
      patIndex += 1
      continue
    if strChar in config.ignoredChars:
      strIndex += 1
      continue

    if strChar == patternChar:
      if recursionLevel < config.maxRecursionLevel and strIndex + 1 < str.len:
        var tempMatches: seq[int] = matches
        let tempScore = matchFuzzySublime(pattern[patIndex..^1], str[(strIndex + 1)..^1], tempMatches, recordMatches, config, recursionLevel + 1, baseIndex + strIndex + 1).score
        if tempScore > bestRecursionScore:
          bestRecursionScore = tempScore
          if recordMatches:
            bestRecursionMatches = move tempMatches

      if recordMatches:
        matches.add(strIndex + baseIndex)

      case scoreState
      of StartMatch, WordBoundryMatch:
        scoreState = LeadingCharMatch

      of CharMatch:
        transition(ConsecutiveMatch)

      of LeadingCharMatch, ConsecutiveMatch:
        consecutiveMatchCount += 1
        scoreState = ConsecutiveMatch
        score += config.stateScores[ConsecutiveMatch] * consecutiveMatchCount

        if scoreState == LeadingCharMatch:
          score += config.stateScores[LeadingCharMatch]

        var onBoundary = (patIndex == high(pattern))
        if not onBoundary and strIndex < high(str):
          let
            nextPatternChar = toLowerAscii(pattern[patIndex + 1])
            nextStrChar     = toLowerAscii(str[strIndex + 1])

          onBoundary = (
            nextStrChar notin {'a'..'z'} and
            nextStrChar != nextPatternChar
          )

        if onBoundary:
          transition(WordBoundryMatch)

      of CharDiff, LeadingCharDiff:
        var isLeadingChar = (
          str[strIndex - 1] notin Letters or
          str[strIndex - 1] in {'a'..'z'} and
          str[strIndex] in {'A'..'Z'}
        )

        if isLeadingChar:
          scoreState = LeadingCharMatch
          #a non alpha or a camel case transition counts as a leading char.
          # Transition the state, but don't give the bonus yet; wait until we verify a consecutive match.
        else:
          transition(CharMatch)

      else:
        discard

      patIndex += 1

    else:
      case scoreState
      of StartMatch:
        transition(LeadingCharDiff)

      of ConsecutiveMatch:
        transition(CharDiff)
        consecutiveMatchCount = 0

      of LeadingCharDiff:
        if unmatchedLeadingCharCount < MaxUnmatchedLeadingChar:
          transition(LeadingCharDiff)
        unmatchedLeadingCharCount += 1

      else:
        transition(CharDiff)

    strIndex += 1

  if patIndex == pattern.len and (strIndex == str.len or str[strIndex] notin Letters):
    score += 10

  if bestRecursionScore > score:
    if recordMatches:
      matches = bestRecursionMatches
    return (bestRecursionScore, bestRecursionScore > 0)

  result = (
    score:   score,
    matched: (score > 0),
  )
