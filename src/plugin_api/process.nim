import std/[options, json, strutils]
import results
import misc/[custom_async, custom_logger, myjsonutils, util, async_process]
import scripting/[expose]
import workspaces/workspace
import service, dispatch_tables, vfs, vfs_service, plugin_service

{.push gcsafe.}
{.push raises: [].}

logCategory "plugin-api-process"

###########################################################################

proc runProcessImpl(self: PluginService, process: string, args: seq[string], workingDir: Option[string] = string.none, eval: bool = false) {.async: (raises: []).} =
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

  except CatchableError as e:
    log lvlError, &"Failed to run process '{process}': {e.msg}"

proc runProcess*(self: PluginService, process: string, args: seq[string], workingDir: Option[string] = string.none, eval: bool = false) {.expose("process").} =
  asyncSpawn self.runProcessImpl(process, args, workingDir, eval)

addGlobalDispatchTable "process", genDispatchTable("process")
