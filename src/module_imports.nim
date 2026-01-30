import "../modules/debugger/debugger.nim"
import "../modules/language_server_ctags.nim"
import "../modules/language_server_regex.nim"
import "../modules/terminal/terminal.nim"
import "../modules/language_server_lsp/language_server_lsp.nim"
import "../modules/language_server_paths.nim"

proc initModules*() =
  init_module_debugger()
  init_module_language_server_ctags()
  init_module_language_server_regex()
  init_module_terminal()
  init_module_language_server_lsp()
  init_module_language_server_paths()

proc shutdownModules*() =
  when declared(shutdown_module_debugger): shutdown_module_debugger()
  when declared(shutdown_module_language_server_ctags): shutdown_module_language_server_ctags()
  when declared(shutdown_module_language_server_regex): shutdown_module_language_server_regex()
  when declared(shutdown_module_terminal): shutdown_module_terminal()
  when declared(shutdown_module_language_server_lsp): shutdown_module_language_server_lsp()
  when declared(shutdown_module_language_server_paths): shutdown_module_language_server_paths()
