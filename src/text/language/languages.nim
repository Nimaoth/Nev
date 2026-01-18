import std/[os, tables]
import results
import misc/[custom_logger, regex, jsonex]
import config_provider

{.push gcsafe.}
{.push raises: [].}

logCategory "language-detection"

proc getLanguageForFile*(config: ConfigStore, filename: string): Result[string, string] =
  if filename == "":
    result.err "Can't determine language for empty filename"
    return

  var extension = filename.splitFile.ext
  if extension.len > 0:
    extension = extension[1..^1]

  let mappings = config.get("language-mappings", newJexObject())
  if mappings.kind != JObject:
    log lvlError, &"Expected object for 'language-mappings' but got {mappings.kind}:\n{mappings.pretty}"

  for (regex, language) in mappings.fields.pairs:
    if language.kind != JString:
      log lvlError, &"Expected string for value in 'language-mappings' but got {language.kind}:\n{language.pretty}"
      continue

    try:
      let r = re(regex)
      if filename.contains(r):
        return language.str.ok
    except RegexError as e:
      log lvlError, &"Invalid regex '{regex}' in language mappings: {e.msg}"

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
    result.err "Unknown extension " & extension
    return

  return languageId.ok
