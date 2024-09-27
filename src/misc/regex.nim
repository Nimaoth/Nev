import std/[strutils]
from glob/regexer import globToRegexString

#[
  Globby from https://github.com/treeform/globby

The MIT License (MIT)

Copyright (c) 2021 Andre von Houck

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
]#

type
  GlobbyError* = object of ValueError

  GlobEntry[T] = object
    path: string
    parts: seq[string] ## The path parts (path split on '/').
    data: T

  GlobTree*[T] = ref object
    data: seq[GlobEntry[T]]

proc len*[T](tree: GlobTree[T]): int =
  ## Return number of paths in the tree.
  tree.data.len

proc add*[T](tree: GlobTree[T], path: string, data: T) =
  ## Add a path to the tree. Can contain multiple entries for the same path.
  if path == "":
    raise newException(GlobbyError, "Path cannot be an empty string")
  let parts = path.split('/')
  for part in parts:
    if part == "":
      raise newException(GlobbyError, "Path cannot contain // or a trailing /")
    if part.contains({'*', '?', '[', ']'}):
      raise newException(GlobbyError, "Path cannot contain *, ?, [ or ]")
  tree.data.add(GlobEntry[T](
    path: path,
    parts: parts,
    data: data
  ))

proc globMatchOne(path, glob: var string, pathStart = 0, globStart = 0): bool =
  ## Match a single entry string to glob.

  proc error(glob: var string) =
    raise newException(GlobbyError, "Invalid glob: `" & glob & "`")

  var
    i = pathStart
    j = globStart
  while j < glob.len:
    if glob[j] == '?':
      discard
    elif glob[j] == '*':
      while true:
        if j == glob.len - 1: # At the end
          return true
        elif glob[j + 1] == '*':
          inc j
        else:
          break
      for k in i ..< path.len:
        if globMatchOne(path, glob, k, j + 1):
          i = k - 1
          return true
      return false
    elif glob[j] == '[':
      inc j
      if j < glob.len and glob[j] == ']': error(glob)
      if j + 3 < glob.len and glob[j + 1] == '-' and glob[j + 3] == ']':
        # Do [A-z] style match.
        if path[i].ord < glob[j].ord or path[i].ord > glob[j + 2].ord:
          return false
        j += 3
      else:
        # Do [ABC] style match.
        while true:
          if j >= glob.len: error(glob)
          elif glob[j] == path[i]:
            while glob[j] != ']':
              if j + 1 >= glob.len: error(glob)
              inc j
            break
          elif glob[j] == '[': error(glob)
          elif glob[j] == ']':
            return false
          inc j
    elif i >= path.len:
      return false
    elif glob[j] != path[i]:
      return false
    inc i
    inc j

  if i == path.len and j == glob.len:
    return true

proc globMatch(
  pathParts, globParts: var seq[string], pathStart = 0, globStart = 0
): bool =
  ## Match a seq string to a seq glob pattern.
  var
    i = pathStart
    j = globStart
  while i < pathParts.len and j < globParts.len:
    if globParts[j] == "*":
      discard
    elif globParts[j] == "**":
      if j == globParts.len - 1: # At the end
        return true
      for k in i ..< pathParts.len:
        if globMatch(pathParts, globParts, k, j + 1):
          i = k - 1
          return true
      return false
    else:
      if not globMatchOne(pathParts[i], globParts[j]):
        return false
    inc i
    inc j

  if i == pathParts.len and j == globParts.len:
    return true

proc globSimplify(globParts: seq[string]): seq[string] =
  ## Simplify backwards ".." and absolute "//".
  for globPart in globParts:
    if globPart == "..":
      if result.len > 0:
        discard result.pop()
    elif globPart == "":
      result.setLen(0)
    else:
      result.add globPart

proc del*[T](tree: GlobTree[T], path: string, data: T) =
  ## Delete a specific path and value from the tree.
  for i, entry in tree.data:
    if entry.path == path and entry.data == data:
      tree.data.delete(i)
      return

proc del*[T](tree: GlobTree[T], glob: string) =
  ## Delete all paths from the tree that match the glob.
  var
    globParts = glob.split('/').globSimplify()
    i = 0
  while i < tree.data.len:
    if tree.data[i].parts.globMatch(globParts):
      tree.data.delete(i)
      continue
    inc i

iterator findAll*[T](tree: GlobTree[T], glob: string): T =
  ## Find all the values that match the glob.
  var globParts = glob.split('/').globSimplify()
  for entry in tree.data.mitems:
    if entry.parts.globMatch(globParts):
      yield entry.data

iterator paths*[T](tree: GlobTree[T]): string =
  ## Iterate all of the paths in the tree.
  for entry in tree.data:
    yield entry.path

proc globMatch*(path, glob: string): bool =
  ## Match a path to a glob pattern.
  var
    paths = path.split('/')
    globs = glob.split('/').globSimplify()
  globMatch(paths, globs)

proc escapeRegex*(s: string): string =
  ## escapes `s` so that it is matched verbatim when used as a regular
  ## expression.
  result = ""
  for c in items(s):
    case c
    of 'a'..'z', 'A'..'Z', '0'..'9', '_':
      result.add(c)
    else:
      result.add("\\x")
      result.add(toHex(ord(c), 2))

import pkg/regex as reg

type Regex* = reg.Regex2
func re*(s: string, flags: reg.RegexFlags = {}): Regex {.raises: [RegexError].} = reg.re2(s, flags)

proc findBounds*(text: string, regex: Regex, start: int): tuple[first: int, last: int] =
  for b in reg.findAllBounds(text, regex, start):
    return (b.a, b.b)
  return (-1, -1)

proc matchLen*(text: string, regex: Regex, start: int): int =
  for b in reg.findAllBounds(text, regex, start):
    return b.b - b.a + 1
  return -1

func contains*(text: string, regex: Regex): bool =
  reg.contains(text, regex)

func match*(text: string, regex: Regex): bool =
  reg.match(text, regex)

iterator findAllBounds*(buf: string, pattern: Regex): tuple[first: int, last: int] =
  var start = 0
  while start < buf.high:
    let bounds = buf.findBounds(pattern, start)
    if bounds.first == -1:
      break
    yield bounds
    start = bounds.last + 1

proc glob*(pattern: string): Regex =
  when defined(js):
    # js doesn't support (?s) syntax in the regex, but we can pass a flag
    # to the regex itself to make it case insensitive
    let regexString = globToRegexString(pattern, isDos=false, ignoreCase=false)
    return reg.re2(regexString, ignoreCase=true)
  else:
    let regexString = globToRegexString(pattern, isDos=false, ignoreCase=true)
    return reg.re2(regexString)

type Globs* = object
  negatedPatterns: seq[string]
  original: seq[string]

proc parseGlobs*(globs: string): Globs =
  result = Globs()
  for line in globs.splitLines():
    # todo: support trailing spaces when escaped with \
    let lineStripped = strutils.strip(line)
    if lineStripped.isEmptyOrWhitespace or lineStripped.startsWith("#"):
      continue

    if lineStripped.startsWith("!"):
      result.negatedPatterns.add lineStripped[1..^1]
    else:
      result.original.add lineStripped

proc includePath*(globs: Globs, path: string): bool  {.raises: [].}=
  try:
    for negatedPattern in globs.negatedPatterns:
      if path.globMatch(negatedPattern):
        return true
    return false
  except GlobbyError:
    return false

proc excludePath*(globs: Globs, path: string): bool {.raises: [].} =
  try:
    for pattern in globs.original:
      if path.globMatch(pattern):
        return true

    return false
  except GlobbyError:
    return false

when isMainModule:
  import std/[strformat]

  proc testGlob(globLines: string, matches: string, notMatches: string) =
    echo &"testing\n{globLines.indent(2)}"
    let globs = globLines.parseGlobs
    let matches = matches.splitLines
    let notMatches = notMatches.splitLines

    for input in matches:
      let inputStripped = strutils.strip(input)
      if inputStripped.len == 0:
        continue
      if not globs.matches(inputStripped):
        echo &"FAIL '{inputStripped}' failed to match on\n{globLines.indent(2)}"

    for input in notMatches:
      let inputStripped = strutils.strip(input)
      if inputStripped.len == 0:
        continue
      if globs.matches(inputStripped):
        echo &"FAIL '{inputStripped}' matched on\n{globLines.indent(2)}"

  testGlob("*", """
    .git
    abc
    a.b
    """, """
    a/b
    a/b/c
    a/b/c/d
    """)

  testGlob("*.git", """
    .git
    """, """
    abc
    a.b
    a/b
    a/b/c
    a/b/c/d
    """)

  testGlob("abc", """
    abc
    """, """
    .git
    a.b
    a/b
    a/b/c
    a/b/c/d
    """)

  testGlob("b", """
    b
    """, """
    a/b
    .git
    a.b
    abc
    a/b/c
    a/b/c/d
    """)

  testGlob("**/b", """
    b
    a/b
    """, """
    .git
    a.b
    abc
    a/b/c
    a/b/c/d
    """)

  testGlob("**/b/**", """
    b
    b/c
    a/b
    a/b/c
    a/b/c/d
    """, """
    .git
    a.b
    abc
    """)

  testGlob("**/*.exe", """
    .exe
    a.exe
    a/a.exe
    a/b/a.exe
    a/b/c/a.exe
    a/b/c/d/a.exe
    """, """
    .git
    a.b
    abc
    """)

  testGlob("**/RiderLink/**", """
    Plugins/Developer/RiderLink
    Plugins/Developer/RiderLink/Source
    Plugins/Developer/RiderLink/Source/RD
    Plugins/Developer/RiderLink/Source/RD/thirdparty
    Plugins/Developer/RiderLink/Source/RD/thirdparty/a.b
    """, """
    .git
    a.b
    abc
    """)

  testGlob("Plugins/Animations", """
    Plugins/Animations
    """, """
    .git
    a.b
    abc
    """)

  echo "ok"