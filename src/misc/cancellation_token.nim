
type CancellationToken* = ref object
  canceled: bool

proc newCancellationToken*(): CancellationToken = CancellationToken()

proc cancel*(token: CancellationToken) =
  token.canceled = true

proc canceled*(token: CancellationToken): bool = token.canceled