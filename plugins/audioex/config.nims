include "../wasm.config.nims"
switch("d", "pluginApiVersion=0")

# Put custom build configs which shouldn't be commited in local.nims
when withDir(thisDir(), fileExists("local.nims")):
  include "local.nims"

# begin Nimble config (version 2)
--noNimblePath
when withDir(thisDir(), system.fileExists("nimble.paths")):
  include "nimble.paths"
# end Nimble config
