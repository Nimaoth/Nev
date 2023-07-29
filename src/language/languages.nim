import std/[options, os]
import custom_logger

proc getLanguageForFile*(filename: string): Option[string] =
  var extension = filename.splitFile.ext
  if extension.len > 0:
    extension = extension[1..^1]

  let languageId = case extension
  of "c", "cc", "inc": "c"
  of "sh": "bash"
  of "cs": "csharp"
  of "cpp", "hpp", "h": "cpp"
  of "css": "css"
  of "go": "go"
  of "hs": "haskell"
  of "html": "html"
  of "java": "java"
  of "js", "jsx", "json": "javascript"
  of "ocaml": "ocaml"
  of "php": "php"
  of "py": "python"
  of "ruby": "ruby"
  of "rs": "rust"
  of "scala": "scala"
  of "ts": "typescript"
  of "nim", "nims": "nim"
  of "zig": "zig"
  else:
    # Unsupported language
    # log(lvlWarn, fmt"Unknown file extension '{extension}'")
    return string.none

  return languageId.some
