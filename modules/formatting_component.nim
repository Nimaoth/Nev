import std/[options, tables]
import nimsumtree/[arc]
import misc/[custom_async]
import vfs, config_provider, service, document
import component

export component

const currentSourcePath2 = currentSourcePath()
include module_base

declareSettings FormatSettings, "formatter":
  ## If true run the formatter when saving.
  declare onSave, bool, false

  ## Command to run. First entry is path to the formatter program, subsequent entries are passed as arguments to the formatter.
  declare command, seq[string], newSeq[string]()

type
  Formatter* = ref object of RootObj
    formatImpl*: proc(self: Formatter, document: Document): Future[void] {.gcsafe, async: (raises: []).}

  FormattingService* = ref object of DynamicService
    formatters: Table[string, Formatter]

  FormattingComponent* = ref object of Component
    vfs: Arc[VFS2]
    config: ConfigStore
    settings: FormatSettings

func serviceName*(_: typedesc[FormattingService]): string = "FormattingService"

# DLL API

proc getFormattingComponent*(self: ComponentOwner): Option[FormattingComponent] {.rtl, gcsafe, raises: [].}
proc newFormattingComponent*(vfs: Arc[VFS2], config: ConfigStore): FormattingComponent {.rtl, gcsafe, raises: [].}

proc formattingComponentFormat(self: FormattingComponent): Future[void] {.rtl, gcsafe, async: (raises: []).}

proc formattingServiceRegisterFormatter(self: FormattingService, name: string, formatter: Formatter) {.rtl, gcsafe, raises: [].}

# Nice wrappers
proc format*(self: FormattingComponent): Future[void] {.async: (raises: []).} = await formattingComponentFormat(self)
proc registerFormatter*(self: FormattingService, name: string, formatter: Formatter) {.inline.} = formattingServiceRegisterFormatter(self, name, formatter)

# Implementation
when implModule:
  import misc/[util, custom_logger, async_process]
  import nimsumtree/[rope]
  import document, text_component

  logCategory "formatting-component"

  var FormattingComponentId: ComponentTypeId = componentGenerateTypeId()

  type FormattingComponentImpl* = ref object of FormattingComponent

  proc formattingServiceRegisterFormatter(self: FormattingService, name: string, formatter: Formatter) {.gcsafe, raises: [].} =
    self.formatters[name] = formatter

  proc getFormattingComponent*(self: ComponentOwner): Option[FormattingComponent] {.gcsafe, raises: [].} =
    return self.getComponent(FormattingComponentId).mapIt(it.FormattingComponent)

  proc newFormattingComponent*(vfs: Arc[VFS2], config: ConfigStore): FormattingComponent =
    return FormattingComponentImpl(
      typeId: FormattingComponentId,
      vfs: vfs,
      config: config,
      settings: FormatSettings.new(config),
      initializeImpl: (proc(self: Component, owner: ComponentOwner) =
        let self = self.FormattingComponent
        owner.Document.preSaveHandlers.add proc(doc: Document): Future[void] {.async: (raises: [])} =
          debugf"pre save {doc.filename}"
          if self.settings.onSave.get():
            await self.format()
      ),
    )

  proc formattingComponentFormat(self: FormattingComponent): Future[void] {.rtl, gcsafe, async: (raises: []).} =
    let services = getServices()
    if services == nil:
      return

    let formattingService = services.getService(FormattingService).getOr:
      return

    let doc = self.owner.Document

    debugf"format {doc.filename}"
    let formatterType = self.config.get("formatter.type", "")
    if formatterType != "":
      if formatterType in formattingService.formatters:
        let formatter = formattingService.formatters[formatterType]
        await formatter.formatImpl(formatter, doc)
      else:
        log lvlError, &"Unknown formatter type '{formatterType}' for file '{doc.filename}'"
      return

    let text = self.owner.getTextComponent().getOr:
      return

    try:
      let command = self.config.get("formatter.command", seq[string])
      if command.len == 0:
        log lvlWarn, &"No formatter configured"
        return

      let formatterPath = command[0]
      let formatterArgs = command[1..^1]

      log lvlInfo, &"Format document '{doc.filename}' with '{formatterPath} {formatterArgs}'"

      let runOnTempFile = true
      if runOnTempFile:
        let ext = doc.filename.splitFile.ext
        let tempFile = await self.vfs.genTempPath(prefix = "format/", suffix = ext)
        try:
          await self.vfs.write(tempFile, text.content)
        except IOError as e:
          log lvlError, &"[format] Failed to write file {tempFile}: {e.msg}\n{e.getStackTrace()}"
          return

        defer:
          asyncSpawn asyncDiscard self.vfs.delete(tempFile)

        discard await runProcessAsync(formatterPath, formatterArgs & @[self.vfs.localize(tempFile)])

        var rope: Rope = Rope.new()
        try:
          await self.vfs.readRope(tempFile, rope.addr)
        except IOError as e:
          log lvlError, &"[format] Failed to load file {tempFile}: {e.msg}\n{e.getStackTrace()}"
          return

        # discard await self.reloadFromRope(rope.clone())

      else:
        discard await runProcessAsync(formatterPath, formatterArgs & @[doc.localizedPath])
        # await self.loadAsync(isReload = true)

    except Exception as e:
      log lvlError, &"Failed to format document '{doc.filename}': {e.msg}\n{e.getStackTrace()}"

  proc init_module_formatting_component*() {.cdecl, exportc, dynlib.} =
    let services = getServices()
    if services == nil:
      log lvlWarn, &"Failed to initialize init_module_formatting_component: no services found"
      return

    let service = FormattingService()
    # service.initImpl = proc(self: Service): Future[Result[void, ref CatchableError]] {.gcsafe, async: (raises: []).} =
    #   return await service.initService()

    services.addService(service)
