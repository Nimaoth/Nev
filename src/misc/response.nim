import std/[json, tables, options, macros]
import misc/[myjsonutils]

{.push gcsafe.}
{.push raises: [].}

type
  ResponseKind* {.pure.} = enum
    Error
    Canceled
    Success

  ResponseError* = object
    code*: int
    message*: string
    data*: JsonNode

  Response*[T] = object
    id*: int
    case kind*: ResponseKind
    of Error:
      error*: ResponseError
    of Canceled:
      discard
    of Success:
      result*: T

proc to*(a: Response[JsonNode], T: typedesc): Response[T] =
  when T is JsonNode:
    return a
  else:
    case a.kind:
    of ResponseKind.Error:
      return Response[T](id: a.id, kind: ResponseKind.Error, error: a.error)
    of ResponseKind.Canceled:
      return Response[T](id: a.id, kind: ResponseKind.Canceled)
    of ResponseKind.Success:
      try:
        when T is string:
          if a.result.kind == JString:
            return Response[T](id: a.id, kind: ResponseKind.Success, result: a.result.str)
          else:
            let error = ResponseError(
              code: -2,
              message: "Failed to convert result to " & $T, data: a.result,
            )
            return Response[T](id: a.id, kind: ResponseKind.Error, error: error)
        else:
          return Response[T](
            id: a.id,
            kind: ResponseKind.Success,
            result: a.result.jsonTo(T, Joptions(allowMissingKeys: true, allowExtraKeys: true)),
          )
      except:
        let error = ResponseError(code: -2, message: "Failed to convert result to " & $T, data: a.result)
        return Response[T](id: a.id, kind: ResponseKind.Error, error: error)

proc to*[K](a: Response[K], T: typedesc): Response[T] =
  when T is JsonNode:
    return a
  else:
    case a.kind:
    of ResponseKind.Error:
      return Response[T](id: a.id, kind: ResponseKind.Error, error: a.error)
    of ResponseKind.Canceled:
      return Response[T](id: a.id, kind: ResponseKind.Canceled)
    of ResponseKind.Success:
      assert false

proc success*[T](value: T): Response[T] =
  return Response[T](kind: ResponseKind.Success, result: value)

proc error*[T](code: int, message: string, data: JsonNode = newJNull()): Response[T] =
  return Response[T](
    kind: ResponseKind.Error,
    error: ResponseError(code: code, message: message, data: data)
  )

proc canceled*[T](): Response[T] =
  return Response[T](kind: ResponseKind.Canceled)

proc isSuccess*[T](response: Response[T]): bool = response.kind == ResponseKind.Success
proc isError*[T](response: Response[T]): bool = response.kind == ResponseKind.Error
proc isCanceled*[T](response: Response[T]): bool = response.kind == ResponseKind.Canceled

proc `$`*(error: ResponseError): string =
  result = "error(" & $error.code & ", " & $error.message
  if error.data != nil:
    result.add ", " & $error.data
  result.add ")"
