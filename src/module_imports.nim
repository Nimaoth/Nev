import "../modules/language_server_ctags.nim"
import "../modules/language_server_paths.nim"

proc initModules*() =
  init_module_language_server_ctags()
  init_module_language_server_paths()
