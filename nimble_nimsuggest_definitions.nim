import dist/nimble/src/nimblepkg/nimscriptapi

var commandLineParams: seq[string]

proc cpFile(a, b: string) = discard

template task(a, b, body: untyped): untyped =
  body

template withDir(a, body: untyped): untyped =
  body

template selfExec(args: varargs[untyped]): untyped =
  discard

template exec(args: varargs[untyped]): untyped =
  discard
