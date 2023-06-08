import custom_async

when not defined(js):
  import std/[asyncnet]
  export asyncnet
else:
  type
    Port* = distinct uint16 ## port type
    AsyncSocket* = ref object
      address: string
      port: Port

  proc newAsyncSocket*(): owned AsyncSocket =
    new result

  proc connect*(socket: AsyncSocket, address: string, port: Port) {.async.} =
    echo "connect"
    socket.address = address
    socket.port = port

  proc close*(socket: AsyncSocket) =
    echo "close"
    discard

  proc send*(socket: AsyncSocket, data: string) {.async.} =
    echo "send"
    discard

  proc recvLine*(socket: AsyncSocket): owned Future[string] {.async.} =
    echo "recvLine"
    return "lol"