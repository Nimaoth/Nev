import platform/platform
import misc/[custom_async, custom_logger]
import service

logCategory "platform-service"

type
  PlatformService* = ref object of Service
    platform*: Platform
    platformSetFuture: Future[void]

func serviceName*(_: typedesc[PlatformService]): string = "PlatformService"

addBuiltinService(PlatformService)

method init*(self: PlatformService): Future[Result[void, ref CatchableError]] {.async: (raises: []).} =
  log lvlInfo, &"PlatformService.init"
  self.platformSetFuture = newFuture[void]()
  try:
    await self.platformSetFuture
  except CatchableError as e:
    result.err(e)
  return ok()

proc setPlatform*(self: PlatformService, platform: Platform) =
  assert self.platform.isNil
  log lvlInfo, &"PlatformService.setPlatform"
  self.platform = platform
  self.platformSetFuture.complete()
