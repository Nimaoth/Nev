import std/[options, os, tables, json]
import misc/[custom_logger, regex, custom_logger]
import config_provider

logCategory "language-detection"

var regexes = initTable[string, Regex]()
proc getRegex*(str: string): Regex =
  if regexes.contains(str):
    return regexes[str]

  let r = re(str)
  regexes[str] = r
  r

proc getLanguageForFile*(config: ConfigProvider, filename: string): Option[string] =
  if filename == "":
    return string.none

  var extension = filename.splitFile.ext
  if extension.len > 0:
    extension = extension[1..^1]

  let mappings = config.getValue[:JsonNode]("language-mappings", newJObject())
  if mappings.kind != JObject:
    log lvlError, &"Expected object for 'language-mappings' but got {mappings.kind}:\n{mappings.pretty}"

  for (regex, language) in mappings.fields.pairs:
    if language.kind != JString:
      log lvlError, &"Expected string for value in 'language-mappings' but got {language.kind}:\n{language.pretty}"
      continue

    let r = getRegex(regex)
    if filename.contains(r):
      return language.str.some

  let languageId = case extension
  of "agda", "lagda": "agda"
  of "c", "cc", "inc": "c"
  of "sh": "bash"
  of "cs": "c_sharp"
  of "cpp", "hpp", "h": "cpp"
  of "css": "css"
  of "go": "go"
  of "hs": "haskell"
  of "html", "htmx": "html"
  of "java": "java"
  of "js", "jsx": "javascript"
  of "json": "json"
  of "ocaml": "ocaml"
  of "php": "php"
  of "py": "python"
  of "ruby": "ruby"
  of "rs": "rust"
  of "scala": "scala"
  of "ts", "tsx": "typescript"
  of "nim", "nims", "nimble": "nim"
  of "zig": "zig"
  of "md": "markdown"
  of "scm": "query"
  else:
    return string.none

  return languageId.some
