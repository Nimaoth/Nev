import std/[asynchttpserver, strutils]
import misc/[custom_async]

template withRequest*(req: Request, body1: untyped): untyped =
  var path {.inject.} = ""
  template route(meth: HttpMethod, pth: string, body2: untyped): untyped =
    if req.reqMethod == meth and req.url.path.startsWith(pth):
      path = req.url.path[pth.len..^1]
      block:
        body2
      return

  template post(pth: string, body2: untyped): untyped {.used.} =
    route(HttpPost, pth, body2)

  template get(pth: string, body2: untyped): untyped {.used.} =
    route(HttpGet, pth, body2)

  template options(pth: string, body2: untyped): untyped {.used.} =
    route(HttpOptions, pth, body2)

  template fallback(body2: untyped): untyped {.used.} =
    body2
    return

  proc handler() {.async.} =
    body1

  await handler()