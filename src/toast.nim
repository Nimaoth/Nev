import std/[options, json]
import results
import platform/platform
import misc/[custom_async, custom_logger, myjsonutils, util, timer]
import scripting/expose
import service, platform_service, dispatch_tables, config_provider

{.push gcsafe.}
{.push raises: [].}

logCategory "toast"

type
  Toast* = object
    timer*: Timer
    title*: string
    message*: string
    color*: string
    progress*: float

  ToastService* = ref object of Service
    platform: Platform
    config: ConfigService
    uiSettings: UiSettings
    toasts*: seq[Toast]

    isUpdating: bool

func serviceName*(_: typedesc[ToastService]): string = "ToastService"

addBuiltinService(ToastService, ConfigService, PlatformService)

method init*(self: ToastService): Future[Result[void, ref CatchableError]] {.async: (raises: []).} =
  log lvlInfo, &"ToastService.init"
  self.platform = self.services.getService(PlatformService).get.platform
  assert self.platform != nil
  self.config = self.services.getService(ConfigService).get
  self.uiSettings = UiSettings.new(self.config.runtime)
  return ok()

proc updateToasts(self: ToastService) {.async.} =
  boolLock(self.isUpdating)
  let maxTime = self.uiSettings.toastDuration.get().float64
  while self.toasts.len > 0:
    var removed = false
    var i = 0
    while i < self.toasts.len:
      let elapsed = self.toasts[i].timer.elapsed.ms
      if elapsed > maxTime:
        self.toasts.removeShift(i)
        removed = true
      else:
        self.toasts[i].progress = elapsed / maxTime
        inc i

    self.platform.requestRender(redrawEverything = removed)

    await sleepAsync(15.milliseconds)

###########################################################################

proc getToastService(): Option[ToastService] =
  {.gcsafe.}:
    if gServices.isNil: return ToastService.none
    return gServices.getService(ToastService)

static:
  addInjector(ToastService, getToastService)

proc showToast*(self: ToastService, title: string, message: string, color: string) {.expose("toast").} =
  log lvlInfo, &"[{title}] {message}"
  self.toasts.add(Toast(timer: startTimer(), title: title, message: message, color: color))
  asyncSpawn self.updateToasts()
  self.platform.requestRender()

addGlobalDispatchTable "toast", genDispatchTable("toast")
