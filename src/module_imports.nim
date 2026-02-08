import "../modules/debugger/debugger.nim"
import "../modules/hover_component.nim"
import "../modules/language_server_ctags.nim"
import "../modules/language_server_regex.nim"
import "../modules/workspace_edit.nim"
import "../modules/command_component.nim"
import "../modules/terminal/terminal.nim"
import "../modules/language_server_lsp/language_server_lsp.nim"
import "../modules/language_server_paths.nim"
import "../modules/formatting_component.nim"
import "../modules/angelscript_formatter.nim"

proc initModules*() =
  init_module_debugger()
  init_module_hover_component()
  init_module_language_server_ctags()
  init_module_language_server_regex()
  init_module_workspace_edit()
  init_module_command_component()
  init_module_terminal()
  init_module_language_server_lsp()
  init_module_language_server_paths()
  init_module_formatting_component()
  init_module_angelscript_formatter()

proc shutdownModules*() =
  when declared(shutdown_module_debugger): shutdown_module_debugger()
  when declared(shutdown_module_hover_component): shutdown_module_hover_component()
  when declared(shutdown_module_language_server_ctags): shutdown_module_language_server_ctags()
  when declared(shutdown_module_language_server_regex): shutdown_module_language_server_regex()
  when declared(shutdown_module_workspace_edit): shutdown_module_workspace_edit()
  when declared(shutdown_module_command_component): shutdown_module_command_component()
  when declared(shutdown_module_terminal): shutdown_module_terminal()
  when declared(shutdown_module_language_server_lsp): shutdown_module_language_server_lsp()
  when declared(shutdown_module_language_server_paths): shutdown_module_language_server_paths()
  when declared(shutdown_module_formatting_component): shutdown_module_formatting_component()
  when declared(shutdown_module_angelscript_formatter): shutdown_module_angelscript_formatter()
