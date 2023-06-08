when defined(js):
  import std/[sequtils]
  import std/[jsffi]
  import custom_async

  type
    WebSocketJs = distinct JsObject
    WebSocketMsgJs = distinct JsObject

    WebSocket* = ref object
      url*: string
      protocols*: seq[string]
      socket: WebSocketJs
      recvBuffer: seq[string]
      sendBuffer: seq[string]

  proc newWebSocketJs(url: cstring): WebSocketJs {.importjs: "new WebSocket(#)".}
  proc sendJs(ws: WebSocketJs, text: cstring) {.importjs: "#.send(#)".}
  proc `onMessage=`(ws: WebSocketJs, callback: proc(msg: WebSocketMsgJs) {.closure.}) {.importjs: "#.onmessage = #".}
  proc `onError=`(ws: WebSocketJs, callback: proc(msg: JsObject) {.closure.}) {.importjs: "#.addEventListener('error', #)".}
  proc readyState(ws: WebSocketJs): int {.importjs: "#.readyState".}
  proc data(msg: WebSocketMsgJs): cstring {.importjs: "#.data".}
  proc console[T](t: T) {.importjs: "console.log(#);".}

  proc newWebSocket*(url: string, protocols: openArray[string] = []): Future[WebSocket] {.async.} =
    var socket = new WebSocket
    socket.url = url
    socket.protocols = @protocols
    socket.socket = newWebSocketJs(url.cstring)
    socket.socket.onMessage = proc(msg: WebSocketMsgJs) =
      socket.recvBuffer.add $msg.data
    socket.socket.onError = proc(msg: JsObject) =
      echo "Error: "
      console(msg)

    return socket

  proc newWebSocket*(url: string, protocol: string): Future[WebSocket] =
    return newWebSocket(url, [protocol])

  proc sendSendBufferWhenReady(ws: WebSocket): Future[void] {.async.} =
    while ws.socket.readyState == 0:
      await sleepAsync(1)

    if ws.socket.readyState != 1:
      return

    # echo "sendSendBufferWhenReady, ready"
    for s in ws.sendBuffer:
      ws.socket.sendJs(s.cstring)
    ws.sendBuffer.setLen 0

  proc send*(ws: WebSocket, text: string): Future[void] {.async.} =
    if ws.socket.readyState == 0:
      # echo "send, not ready"
      ws.sendBuffer.add text
      asyncCheck ws.sendSendBufferWhenReady()
    elif ws.socket.readyState == 1:
      # echo "send, ready, ", ws.sendBuffer.len
      for s in ws.sendBuffer:
        ws.socket.sendJs(s.cstring)
      ws.sendBuffer.setLen 0

      ws.socket.sendJs(text.cstring)
    else:
      return

  proc receiveStrPacket*(ws: WebSocket): Future[string] {.async.} =
    while ws.recvBuffer.len == 0:
      if ws.socket.readyState > 1:
        raise newException(IOError, "web socket closed")
      await sleepAsync(1)
    let res = move ws.recvBuffer[0]
    ws.recvBuffer.delete(0..0)
    return res

else:
  import ws
  export ws