import std/[options]
import custom_async, array_buffer

import std/[httpclient]

var clients: seq[AsyncHttpClient] = @[]
var totalClients = 0
const maxClients = 25

proc getClient(): Future[AsyncHttpClient] {.async.} =
  while clients.len == 0:
    if totalClients < maxClients:
      inc totalClients
      return newAsyncHttpClient(userAgent = "Thunder Client (https://www.thunderclient.com)")
    await sleepAsync(10)
  return clients.pop

template withClient(client, body: untyped): untyped =
  block:
    let client = await getClient()
    defer:
      clients.add client
    body

proc httpGet*(url: string, authToken: Option[string] = string.none): Future[string] {.async.} =
  var headers = newHttpHeaders()
  if authToken.isSome:
    headers.add("Authorization", authToken.get)

  withClient client:
    var response = await client.request(url, HttpGet, headers=headers)
    let body = await response.body
    return body

proc httpPost*(url: string, content: string, authToken: Option[string] = string.none): Future[string] {.async.} =
  var headers = newHttpHeaders()
  if authToken.isSome:
    headers.add("Authorization", authToken.get)

  headers.add("content-type", "text/plain")

  withClient client:
    let response = client.request(url, HttpPost, body=content, headers=headers).await
    return response.body.await

proc httpPost*(url: string, content: ArrayBuffer, authToken: Option[string] = string.none): Future[string] {.async.} =
  var str = newStringOfCap(content.buffer.len)
  str.setLen(content.buffer.len)
  for i in 0..content.buffer.high:
    str[i] = content.buffer[i].char

  var headers = newHttpHeaders()
  if authToken.isSome:
    headers.add("Authorization", authToken.get)

  headers.add("content-type", "application/octet-stream")

  withClient client:
    let response = client.request(url, HttpPost, body=str, headers=headers).await
    return response.body.await
