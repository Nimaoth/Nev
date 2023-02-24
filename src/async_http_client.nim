import custom_async

when defined(js):

  proc getAsyncJs(url: cstring): Future[cstring] {.importc.}

  proc httpGet*(url: string): Future[string] {.async.} =
    let cstr = await getAsyncJs(url.cstring)
    return $cstr

else:
  import std/[httpclient]

  proc httpGet*(url: string): Future[string] {.async.} =
    var client = newAsyncHttpClient(userAgent = "Thunder Client (https://www.thunderclient.com)")
    var response = await client.get(url)
    let body = await response.body
    return body