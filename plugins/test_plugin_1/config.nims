include "../wasm.config.nims"

# Put custom build configs which shouldn't be commited in local.nims
when withDir(thisDir(), fileExists("local.nims")):
  include "local.nims"
