when defined(js):
  import std/asyncjs
  export asyncjs

  template asyncCheck*(body: untyped): untyped = discard body
  proc sleepAsync*(ms: int): Future[void] {.importjs: "(new Promise(resolve => setTimeout(resolve, #)))".}
else:
  import std/asyncdispatch, std/asyncfile, std/asyncfutures
  export asyncdispatch, asyncfile, asyncfutures