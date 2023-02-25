import std/[options]
import custom_async

when defined(js):

  proc getAsyncJs(url: cstring, authToken: cstring): Future[cstring] {.importc.}

  proc httpGet*(url: string, authToken: Option[string] = string.none): Future[string] {.async.} =
    let cstr = await getAsyncJs(url.cstring, authToken.get("").cstring)
    return $cstr

else:
  import std/[httpclient]

  proc httpGet*(url: string, authToken: Option[string] = string.none): Future[string] {.async.} =
    var headers = newHttpHeaders()
    if authToken.isSome:
      headers.add("Authorization", authToken.get)

    var client = newAsyncHttpClient(userAgent = "Thunder Client (https://www.thunderclient.com)", headers = headers)
    var response = await client.get(url, )
    let body = await response.body
    return body