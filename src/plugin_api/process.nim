import std/[options, json, strutils]
import results
import misc/[custom_async, custom_logger, myjsonutils, util, async_process]
import scripting/[expose, scripting_base]
import workspaces/workspace
import service, dispatch_tables, vfs, vfs_service

{.push gcsafe.}
{.push raises: [].}

logCategory "plugin-api-process"

###########################################################################

proc runProcessImpl(self: PluginService, process: string, args: seq[string], callback: Option[string] = string.none, workingDir: Option[string] = string.none, eval: bool = false) {.async: (raises: []).} =
  type ResultType = tuple[output: string, err: string]

  let workingDir = if workingDir.getSome(wd):
    let vfs = self.services.getService(VFSService).get.vfs
    vfs.localize(wd)
  else:
    let workspace = self.services.getService(Workspace).get
    workspace.path

  try:
    let (output, err) = await runProcessAsyncOutput(process, args, workingDir=workingDir, eval=eval)
    log lvlDebug, &"runProcess '{process} {args.join($' ')}' in '{workingDir}'"
    if callback.getSome(c):
      discard self.callScriptAction(c, (output: output, err: err).some.toJson)

  except CatchableError as e:
    log lvlError, &"Failed to run process '{process}': {e.msg}"
    if callback.getSome(c):
      discard self.callScriptAction(c, ResultType.none.toJson)

proc runProcess*(self: PluginService, process: string, args: seq[string], callback: Option[string] = string.none, workingDir: Option[string] = string.none, eval: bool = false) {.expose("process").} =
  asyncSpawn self.runProcessImpl(process, args, callback, workingDir, eval)

addGlobalDispatchTable "process", genDispatchTable("process")
