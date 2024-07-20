import std/[options, os]
import misc/custom_logger

proc getLanguageForFile*(filename: string): Option[string] =
  var extension = filename.splitFile.ext
  if extension.len > 0:
    extension = extension[1..^1]

  let languageId = case extension
  of "agda", "lagda": "agda"
  of "c", "cc", "inc": "c"
  of "sh": "bash"
  of "cs": "csharp"
  of "cpp", "hpp", "h": "cpp"
  of "css": "css"
  of "go": "go"
  of "hs": "haskell"
  of "html", "htmx": "html"
  of "java": "java"
  of "js", "jsx", "json": "javascript"
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
    # Unsupported language
    # log(lvlWarn, fmt"Unknown file extension '{extension}'")
    return string.none

  return languageId.some
