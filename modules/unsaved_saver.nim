#use layout event_service

##[
## unsaved_saver

Saves __unsaved__ changes to a temp folder in `app://unsaved` for untitled files
and `ws0://.nev/unsaved` for existing files.

]##

import config_provider

type
  UnsavedBehaviour* = enum None = "none", Temp = "temp", Real = "real"

declareSettings UnsavedSettings, "unsaved":
  ## How often (in seconds) the editor auto saves unsaved files. Set to 0 to disable auto saving.
  declare interval, int, 60

  ## What to do with unsaved files.
  ## `none` - Don't save unsaved files automatically. Files are only saved through the explicit `save` command
  ## `temp` - Save unsaved files to temp files in `app://unsaved` (for non-existing files) or `ws0://.nev/unsaved` for existing files.
  ## `real` - Save existing files to the actual real file. Non-existing files are still saved to `app://unsaved`
  declare behaviour, UnsavedBehaviour, UnsavedBehaviour.None

const currentSourcePath2 = currentSourcePath()
include module_base

# Implementation
when implModule:
  import std/[options, json, strformat, uri, times]
  import misc/[custom_logger, util, myjsonutils, custom_async, id, array_set, delayed_task]
  import document, document_editor, service, event_service, config_component, layout/layout, vfs_service, vfs, text_component

  logCategory "unsaved-saver"

  proc deleteOldUnsavedFiles() {.async: (raises: []).} =
    ## Go through `ws0://.nev/unsaved` using getDirectoryListing and delete files older than corresponding real file
    ## file names are uris, decode with decodeUrl and treat as vsf path
    let services = getServices()
    if services == nil:
      log lvlWarn, &"Failed to run deleteOldUnsavedFiles: no services found"
      return

    let vfs = services.getService(VFSService).get.vfs2
    const unsavedDir = "ws0://.nev/unsaved"

    try:
      let list = await vfs.getDirectoryListing(unsavedDir)
      for encodedPath in list.files:
        let unsavedPath = unsavedDir // encodedPath
        let realPath = encodedPath.decodeUrl

        let realKind = await vfs.getFileKind(realPath)
        if realKind.isNone or realKind.get != FileKind.File:
          continue

        let unsavedLocal = vfs.localize(unsavedPath)
        let realLocal = vfs.localize(realPath)

        if not fileExists(unsavedLocal) or not fileExists(realLocal):
          continue

        let unsavedMTime = getLastModificationTime(unsavedLocal)
        let realMTime = getLastModificationTime(realLocal)
        if unsavedMTime < realMTime:
          log lvlInfo, &"Delete stale unsaved '{unsavedPath}' (real file newer: '{realPath}')"
          discard await vfs.delete(unsavedPath)

    except CatchableError as e:
      log lvlError, &"Failed to delete old unsaved files: {e.msg}"

  proc saveUnsavedFiles(behaviour: UnsavedBehaviour) {.async: (raises: []).} =
    if behaviour == UnsavedBehaviour.None:
      return

    let services = getServices()
    if services == nil:
      log lvlWarn, &"Failed to initialize init_module_unsaved_saver: no services found"
      return

    let layout = services.getService(LayoutService).get
    let vfs = services.getService(VFSService).get.vfs2

    try:
      var docs: seq[Document] = @[]
      for view in layout.allViews:
        if not (view of EditorView):
          continue
        let view = view.EditorView
        let doc = view.editor.currentDocument
        if doc.isNil:
          continue
        if doc.getConfigComponent().getSome(config) and not config.get("editor.save-in-session", true):
          continue
        if doc.filename == "local://log" or doc.filename == "ed://.command-line" or doc.filename == "local://.debugger-output":
          continue

        let isDirty = not doc.requiresLoad and doc.lastSavedRevision != doc.revision
        if not isDirty:
          continue

        discard doc.getTextComponent().getOr:
          continue

        docs.incl(doc)

      if docs.len > 0:
        log lvlInfo, &"Save {docs.len} unsaved files"
        for doc in docs:
          var fileBehaviour = behaviour
          var targetPath = ""
          if doc.filename == "":
            targetPath = &"app://unsaved/{doc.uniqueId}"
            fileBehaviour = UnsavedBehaviour.Temp
          else:
            let fileKind = await vfs.getFileKind(doc.filename)
            if fileKind.isNone:
              targetPath = &"app://unsaved/{doc.uniqueId}"
              fileBehaviour = UnsavedBehaviour.Temp
            else:
              targetPath = &"ws0://.nev/unsaved/{doc.filename.encodeUrl}"

          case fileBehaviour
          of UnsavedBehaviour.None:
            discard
          of UnsavedBehaviour.Temp:
            let text = doc.getTextComponent().getOr:
              continue

            log lvlInfo, &"Save unsaved '{doc.filename}' -> '{targetPath}'"
            await vfs.write(targetPath, text.content)

          of UnsavedBehaviour.Real:
            await doc.save()

    except CatchableError as e:
      log lvlError, &"Error: {e.msg}"

    await deleteOldUnsavedFiles()

  proc init_module_unsaved_saver*() {.cdecl, exportc, dynlib.} =
    let services = getServices()
    if services == nil:
      log lvlWarn, &"Failed to initialize init_module_unsaved_saver: no services found"
      return

    let config = services.getService(ConfigService).get
    let events = services.getService(EventService).get
    let documents = services.getService(DocumentEditorService).get
    let vfs = services.getService(VFSService).get.vfs2
    let settings = UnsavedSettings.new(config.runtime)

    var first = true
    var task: DelayedTask = nil
    task = startDelayedPausedAsync(max(settings.interval.get() * 1000, 1000), true):
      if first:
        first = false
        return
      task.interval = max(settings.interval.get() * 1000, 1000)
      await saveUnsavedFiles(settings.behaviour.get())
    task.schedule()

    proc handleShutdown(event, payload: string) {.gcsafe, raises: [].} =
      log lvlWarn, &"handleShutdown {event}"
      waitFor saveUnsavedFiles(settings.behaviour.get())

    events.listen(newId(), "app/shutdown", handleShutdown)

    proc handleEditorRegistered(event, payload: string) {.gcsafe, raises: [].} =
      try:
        let id = payload.parseInt.EditorIdNew
        if documents.getEditor(id).getSome(editor):
          let doc = editor.currentDocument
          if doc.isNil:
            return

          var targetPath = ""
          if doc.filename == "":
            targetPath = &"app://unsaved/{doc.uniqueId}"
          else:
            let fileKind = waitFor vfs.getFileKind(doc.filename)
            if fileKind.isNone:
              targetPath = &"app://unsaved/{doc.uniqueId}"
            else:
              targetPath = &"ws0://.nev/unsaved/{doc.filename.encodeUrl}"

          let fileKind = waitFor vfs.getFileKind(targetPath)
          if fileKind.isSome:
            let unsavedLocal = vfs.localize(targetPath)
            let realLocal = vfs.localize(doc.filename)
            if doc.filename != "" and fileExists(unsavedLocal) and fileExists(realLocal):
              let unsavedMTime = getLastModificationTime(unsavedLocal)
              let realMTime = getLastModificationTime(realLocal)
              if realMTime > unsavedMTime:
                log lvlInfo, &"Real file '{realLocal}' newer than temp '{unsavedLocal}', don't reload"
                return

            doc.load(targetPath, temp = true)

      except CatchableError as e:
        log lvlError, &"Error: {e.msg}"

    events.listen(newId(), "editor/*/registered", handleEditorRegistered)
