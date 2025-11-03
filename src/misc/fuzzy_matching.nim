import std/[strutils, math]
import misc/timer
import text/diff
import std/strformat

{.push gcsafe.}
{.push raises: [].}

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
    MatchPercentage     ## Increase score when the amount the matched chars is closer to the length of the input.
    CaseMismatch        ## Penalty if the case matches
    UpperCaseMatch      ## Score if the pattern and input are both upper case

  FuzzyMatchConfig* = object
    stateScores*: array[ScoreCard, int] = [
      StartMatch:       -1000,
      LeadingCharDiff:  -30,
      CharDiff:         -10,
      CharMatch:        0,
      ConsecutiveMatch: 50,
      LeadingCharMatch: 100,
      WordBoundryMatch: 200,
      PatternOversize:  -30,
      MatchPercentage:  350,
      CaseMismatch:     -10,
      UpperCaseMatch:   100,
    ]
    matchPercentagePower*: float64 = 1
    ignoredChars*: set[char] = {'_', ' ', '.'}
    maxRecursionLevel*: int = 4
    timeoutMs*: float64 = 15
    useDiff*: bool = false

var defaultPathMatchingConfig* = FuzzyMatchConfig(ignoredChars: {' '})
var defaultCompletionMatchingConfig* = FuzzyMatchConfig(ignoredChars: {' '})

proc matchFuzzySublime*(pattern, str: openArray[char], matches: var seq[int], recordMatches: bool, config: FuzzyMatchConfig = FuzzyMatchConfig(), recursionLevel: int = 0, baseIndex: int = 0, startTime: Timer = startTimer()): tuple[score: int, matched: bool]


proc matchFuzzyDiff*(pattern, str: openArray[char], matches: var seq[int], recordMatches: bool, config: FuzzyMatchConfig = FuzzyMatchConfig(), recursionLevel: int = 0, baseIndex: int = 0, startTime: Timer = startTimer()): tuple[score: int, matched: bool] =
  if pattern.len == 0:
    return (1, true)
  template log(msg: string): untyped =
    when isMainModule:
      echo "".indent(recursionLevel), "'", pattern.join(""), "' ~ '", str.join(""), "': ", msg

  var
    scoreState = StartMatch
    unmatchedLeadingCharCount = 0
    consecutiveMatchCount = 0
    strIndex = 0
    patIndex = 0
    score = 0

  template transition(nextState) =
    scoreState = nextState
    log("transition " & $nextState & ": " & $score & " -> " & $(score + config.stateScores[scoreState]))
    score += config.stateScores[scoreState]

  template matchChar(): untyped =
    log("matchChar " & $strIndex & ": '" & $pattern[patIndex] & "' ~ '" & $str[strIndex] & "', " & $scoreState)
    case scoreState
    of StartMatch, WordBoundryMatch:
      scoreState = LeadingCharMatch
      if strIndex == 0:
        log("transition " & $LeadingCharMatch & ": " & $score & " -> " & $(score + config.stateScores[LeadingCharMatch]))
        score += config.stateScores[LeadingCharMatch]

    of CharMatch:
      transition(ConsecutiveMatch)

    of LeadingCharMatch, ConsecutiveMatch:
      if scoreState == LeadingCharMatch:
        log("transition " & $LeadingCharMatch & ": " & $score & " -> " & $(score + config.stateScores[LeadingCharMatch]))
        score += config.stateScores[LeadingCharMatch]

      consecutiveMatchCount += 1
      scoreState = ConsecutiveMatch
      log("consecutive match: " & $score & " -> " & $(score + config.stateScores[ConsecutiveMatch] * consecutiveMatchCount) & ", consecutive " & $consecutiveMatchCount)
      score += config.stateScores[ConsecutiveMatch] * consecutiveMatchCount

      var onBoundary = (patIndex == high(pattern))
      if not onBoundary and strIndex < high(str):
        let
          nextPatternChar = pattern[patIndex + 1]
          nextStrChar     = str[strIndex + 1]
          nextMatch = nextPatternChar.toLowerAscii == nextStrChar.toLowerAscii

        onBoundary = nextMatch and str[strIndex] notin {'A'..'Z'} and nextStrChar in {'A'..'Z'}
        # onBoundary = (
        #   nextStrChar notin {'a'..'z'} and
        #   nextStrChar != nextPatternChar
        # )

      # if onBoundary:
      #   transition(WordBoundryMatch)

    of CharDiff, LeadingCharDiff:
      var isLeadingChar = (
        strIndex > 0 and
        (str[strIndex - 1] notin Letters or str[strIndex - 1] in {'a'..'z'}) and str[strIndex] in {'A'..'Z'}
      )

      if isLeadingChar:
        scoreState = LeadingCharMatch
        #a non alpha or a camel case transition counts as a leading char.
        # Transition the state, but don't give the bonus yet; wait until we verify a consecutive match.
      else:
        log("consecutive match2: " & $score & " -> " & $(score + config.stateScores[ConsecutiveMatch] * consecutiveMatchCount) & ", consecutive " & $consecutiveMatchCount)
        score += config.stateScores[ConsecutiveMatch] * consecutiveMatchCount
        transition(CharMatch)

    else:
      discard

    if recordMatches:
      matches.add(strIndex)
    inc strIndex
    inc patIndex
    inc matchCount

  proc eq(a, b: char): bool {.gcsafe.} =
    return a.toLowerAscii == b.toLowerAscii

  let d = diff(pattern, str, eq)
  log $d
  var matchCount = 0
  for op in d.ops:
    if op.new.a == 0:
      transition(LeadingCharDiff)

    while strIndex < op.new.a:
      matchChar()

    let insertedChars = op.new.b - op.new.a
    consecutiveMatchCount = max(consecutiveMatchCount - insertedChars, 0)
    log("diff: " & $score & " -> " & $(score + config.stateScores[CharDiff] * insertedChars) & ", inserted " & $insertedChars)
    score += config.stateScores[CharDiff] * insertedChars
    strIndex = op.new.b
    patIndex = op.old.b
    transition(CharDiff)

  while strIndex < str.len:
    matchChar()

  if pattern.len > str.len:
    log("oversize: " & $score & " -> " & $(score + config.stateScores[PatternOversize] * (pattern.len - str.len)) & ", oversize " & $(pattern.len - str.len))
    score += config.stateScores[PatternOversize] * (pattern.len - str.len)

  let matchPercentage = min(matchCount.float64 / str.len.float64, 1)
  log &"matchPercentage: {matchPercentage}"
  # if matchPercentage > 0.9:
  #   echo matchPercentage, ": ", score, " + ", pow(matchPercentage, config.matchPercentagePower) * config.stateScores[MatchPercentage].float64, " -> ", score + (pow(matchPercentage, config.matchPercentagePower) * config.stateScores[MatchPercentage].float64).int
  log("match percent: " & $score & " -> " & $(score + (pow(matchPercentage, config.matchPercentagePower) * config.stateScores[MatchPercentage].float64).int) & ", match percent " & $matchPercentage)
  score += (pow(matchPercentage, config.matchPercentagePower) * config.stateScores[MatchPercentage].float64).int
  result.score = score
  result.matched = result.score > 0

proc matchFuzzySublime*(pattern, str: openArray[char], matches: var seq[int], recordMatches: bool, config: FuzzyMatchConfig = FuzzyMatchConfig(), recursionLevel: int = 0, baseIndex: int = 0, startTime: Timer = startTimer()): tuple[score: int, matched: bool] =
  if pattern.len == 0:
    return (1, true)

  template log(msg: string): untyped =
    when false:
      echo "".indent(recursionLevel), "'", pattern.join(""), "' ~ '", str.join(""), "': ", msg

  log "matchFuzzySublime"
  defer:
    log &"matchFuzzySublime -> {result.score}"

  if pattern.len == 0 or str.len == 0:
    return (0, false)

  var
    scoreState = StartMatch
    unmatchedLeadingCharCount = 0
    consecutiveMatchCount = 0
    strIndex = 0
    patIndex = 0
    score = 0

  if config.timeoutMs >= 0 and startTime.elapsed.ms > config.timeoutMs:
    return (0, false)

  if recursionLevel > config.maxRecursionLevel:
    return (score: int.low, matched: false)

  if pattern.len > str.len:
    score += config.stateScores[PatternOversize] * (pattern.len - str.len)

  template transition(nextState) =
    scoreState = nextState
    score += config.stateScores[scoreState]

  var bestRecursionMatches: seq[int]
  var bestRecursionScore = int.low

  var matchCount = 0

  while (strIndex < str.len) and (patIndex < pattern.len):
    let
      patternChar = pattern[patIndex].toLowerAscii
      strChar     = str[strIndex].toLowerAscii

    if config.timeoutMs >= 0 and startTime.elapsed.ms > config.timeoutMs:
      break

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
        let tempScore = matchFuzzySublime(pattern[patIndex..^1], str[(strIndex + 1)..^1], tempMatches, recordMatches, config, recursionLevel + 1, baseIndex + strIndex + 1, startTime).score
        if tempScore > bestRecursionScore:
          bestRecursionScore = tempScore
          if recordMatches:
            bestRecursionMatches = move tempMatches

      # if recursionLevel < config.maxRecursionLevel and patIndex + 1 < pattern.len:
      #   var tempMatches: seq[int] = matches
      #   let tempScore = matchFuzzySublime(pattern[(patIndex + 1)..^1], str[strIndex..^1], tempMatches, recordMatches, config, recursionLevel + 1, baseIndex + strIndex, startTime).score
      #   if tempScore > bestRecursionScore:
      #     bestRecursionScore = tempScore
      #     if recordMatches:
      #       bestRecursionMatches = move tempMatches

      inc matchCount

      if recordMatches:
        matches.add(strIndex + baseIndex)

      let caseMismatch = pattern[patIndex].isLowerAscii != str[strIndex].isLowerAscii
      if caseMismatch:
        score += config.stateScores[CaseMismatch]
      elif pattern[patIndex].isUpperAscii and str[strIndex].isUpperAscii:
        score += config.stateScores[UpperCaseMatch]

      case scoreState
      of StartMatch, WordBoundryMatch:
        scoreState = LeadingCharMatch
        if strIndex == 0:
          score += config.stateScores[LeadingCharMatch]

      of CharMatch:
        transition(ConsecutiveMatch)

      of LeadingCharMatch, ConsecutiveMatch:
        if scoreState == LeadingCharMatch:
          score += config.stateScores[LeadingCharMatch]

        consecutiveMatchCount += 1
        scoreState = ConsecutiveMatch
        score += config.stateScores[ConsecutiveMatch] * consecutiveMatchCount

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

  let matchPercentage = matchCount.float64 / str.len.float64
  score += (pow(matchPercentage, config.matchPercentagePower) * config.stateScores[MatchPercentage].float64).int

  if bestRecursionScore > score:
    if recordMatches:
      matches = bestRecursionMatches
    return (bestRecursionScore, bestRecursionScore > 0)

  result = (
    score:   score,
    matched: (score > 0),
  )

proc matchFuzzySublime*(pattern, str: openArray[char], config: FuzzyMatchConfig = FuzzyMatchConfig()): tuple[score: int, matched: bool] =
  var matches: seq[int]
  return matchFuzzySublime(pattern, str, matches, false, config)

proc matchFuzzyDiff*(pattern, str: openArray[char], config: FuzzyMatchConfig = FuzzyMatchConfig()): tuple[score: int, matched: bool] =
  var matches: seq[int]
  return matchFuzzyDiff(pattern, str, matches, false, config)

proc matchFuzzy*(pattern, str: openArray[char], config: FuzzyMatchConfig = FuzzyMatchConfig()): tuple[score: int, matched: bool] =
  var matches: seq[int]
  if config.useDiff:
    return matchFuzzyDiff(pattern, str, matches, false, config)
  else:
    return matchFuzzySublime(pattern, str, matches, false, config)

proc matchFuzzy*(pattern, str: openArray[char], matches: var seq[int], recordMatches: bool, config: FuzzyMatchConfig = FuzzyMatchConfig(), recursionLevel: int = 0, baseIndex: int = 0, startTime: Timer = startTimer()): tuple[score: int, matched: bool] =
  if config.useDiff:
    return matchFuzzyDiff(pattern, str, matches, recordMatches, config)
  else:
    return matchFuzzySublime(pattern, str, matches, recordMatches, config)

when isMainModule:
  var pattern = "actorcp"
  var strs = [
    # "text_editor",
    # "texxt_editor",
    # "MirrorActorCommand.cpp",
    "ActorChannel.cpp",
    # "AvaCineCameraActor.cpp",
    # "AvaViewportDataActor.cpp",
    # "CineCameraActor.cpp",
    "Actor.cpp",
    # "CameraActor.cpp",
    # "MapBuildDataActor.cpp",
    # "Crc.cpp",
    # "Amp.cpp",
    # "ActorComponent.cpp",
    "ActorComponent.h",
  ]
  var c = defaultCompletionMatchingConfig
  c.useDiff = true
  for s in strs:
    echo "Score ", s
    # var score = pattern.matchFuzzySublime(s, c).score
    var matches: seq[int]
    var score = pattern.matchFuzzy(s, matches, true, c).score
    echo "  -> ", score, ", ", matches
