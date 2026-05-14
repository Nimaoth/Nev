#use theme
import platform
import misc/[custom_async, custom_logger, util, timer]
import service, config_provider

const currentSourcePath2 = currentSourcePath()
include module_base

{.push gcsafe.}
{.push raises: [].}

type
  Toast* = object
    timer*: Timer
    title*: string
    message*: string
    color*: string
    progress*: float

  ToastService* = ref object of DynamicService
    platform: Platform
    config: ConfigService
    uiSettings: UiSettings
    toasts*: seq[Toast]

    isUpdating: bool

func serviceName*(_: typedesc[ToastService]): string = "ToastService"

# DLL API
{.push modrtl, gcsafe, raises: [].}
proc showToast*(self: ToastService, title: string, message: string, color: string)
{.pop.}

# Implementation
when implModule:
  import std/[options, json]
  import results
  import scripting/expose
  import misc/[myjsonutils]
  import dispatch_tables

  logCategory "toast"

  proc initToastService(self: ToastService) =
    log lvlInfo, &"ToastService.init"
    self.platform = self.services.getServiceChecked(PlatformService).platform
    assert self.platform != nil
    self.config = self.services.getServiceChecked(ConfigService)
    self.uiSettings = UiSettings.new(self.config.runtime)

  proc updateToasts(self: ToastService) {.async.} =
    boolLock(self.isUpdating)
    let maxTime = self.uiSettings.toast.duration.get().float64
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
      if getServices().isNil: return ToastService.none
      return getServices().getService(ToastService)

  static:
    addInjector(ToastService, getToastService)

  proc showToast*(self: ToastService, title: string, message: string, color: string) {.expose("toast").} =
    log lvlInfo, &"[{title}] {message}"
    self.toasts.add(Toast(timer: startTimer(), title: title, message: message, color: color))
    asyncSpawn self.updateToasts()
    self.platform.requestRender()

  addGlobalDispatchTable "toast", genDispatchTable("toast")

  proc init_module_toast*() {.cdecl, exportc, dynlib.} =
    getServices().addService(ToastService(
      initImpl: proc(self: Service): Future[Result[void, ref CatchableError]] {.gcsafe, async: (raises: []).} =
        initToastService(self.ToastService)
        return ok()
    ))
