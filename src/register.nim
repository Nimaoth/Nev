import std/strutils
import nimsumtree/rope

type
  RegisterKind* {.pure.} = enum Text, Rope
  Register* = object
    case kind*: RegisterKind
    of RegisterKind.Text:
      text*: string
    of RegisterKind.Rope:
      rope*: Rope

func clone*(register: Register): Register =
  case register.kind
  of Text: Register(kind: Text, text: register.text)
  of Rope: Register(kind: Rope, rope: register.rope.clone())

proc getText*(register: Register): string =
  case register.kind
  of RegisterKind.Text:
    return register.text
  of RegisterKind.Rope:
    return $register.rope

proc numLines*(register: Register): int =
  case register.kind
  of RegisterKind.Text:
    return register.text.count('\n') + 1
  of RegisterKind.Rope:
    return register.rope.lines
