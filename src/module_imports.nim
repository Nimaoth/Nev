when not defined(useDynlib):
  import "../modules/terminal_platform/terminal_platform.nim"
  import "../modules/status_line.nim"
  import "../modules/text_editor_component.nim"
  import "../modules/register.nim"
  import "../modules/command_service.nim"
  import "../modules/layout/layout.nim"
  import "../modules/command_server.nim"
  import "../modules/stats.nim"
  import "../modules/plugin_service.nim"
  import "../modules/terminal/terminal.nim"
  import "../modules/formatting_component.nim"
  import "../modules/command_component.nim"
  import "../modules/hover_component.nim"
  import "../modules/snippet_component.nim"
  import "../modules/treesitter_component.nim"
  import "../modules/contextline_component.nim"
  import "../modules/workspace_edit.nim"
  import "../modules/decoration_component.nim"
  import "../modules/event_service.nim"
  import "../modules/command_line.nim"
  import "../modules/search_component.nim"
  import "../modules/move_database.nim"
  import "../modules/text/text.nim"
  import "../modules/wasm_engine.nim"
  import "../modules/plugin_system_wasm/plugin_system_wasm.nim"
  import "../modules/unsaved_saver.nim"
  import "../modules/language_server_document_completion.nim"
  import "../modules/undo_tree.nim"
  import "../modules/language_server_paths.nim"
  import "../modules/angelscript_formatter.nim"
  import "../modules/debugger/debugger.nim"
  import "../modules/dashboard.nim"
  import "../modules/vcs_git.nim"
  import "../modules/vcs_perforce.nim"
  import "../modules/vim.nim"
  import "../modules/language_server_ctags.nim"
  import "../modules/log.nim"
  import "../modules/language_server_lsp/language_server_lsp.nim"
  import "../modules/language_server_regex.nim"
  import "../modules/language_server_ue_as.nim"
  import "../modules/language_server_ue_cpp.nim"
  import "../modules/lsp_server.nim"
  import "../modules/log_terminal.nim"
  import "../modules/gui_platform/gui_platform.nim"
  import "../modules/markdown_component.nim"
  import "../modules/git_ui.nim"

proc initModules*() =
  when declared(init_module_terminal_platform): init_module_terminal_platform()
  when declared(init_module_status_line): init_module_status_line()
  when declared(init_module_text_editor_component): init_module_text_editor_component()
  when declared(init_module_register): init_module_register()
  when declared(init_module_command_service): init_module_command_service()
  when declared(init_module_layout): init_module_layout()
  when declared(init_module_command_server): init_module_command_server()
  when declared(init_module_stats): init_module_stats()
  when declared(init_module_plugin_service): init_module_plugin_service()
  when declared(init_module_terminal): init_module_terminal()
  when declared(init_module_formatting_component): init_module_formatting_component()
  when declared(init_module_command_component): init_module_command_component()
  when declared(init_module_hover_component): init_module_hover_component()
  when declared(init_module_snippet_component): init_module_snippet_component()
  when declared(init_module_treesitter_component): init_module_treesitter_component()
  when declared(init_module_contextline_component): init_module_contextline_component()
  when declared(init_module_workspace_edit): init_module_workspace_edit()
  when declared(init_module_decoration_component): init_module_decoration_component()
  when declared(init_module_event_service): init_module_event_service()
  when declared(init_module_command_line): init_module_command_line()
  when declared(init_module_search_component): init_module_search_component()
  when declared(init_module_move_database): init_module_move_database()
  when declared(init_module_text): init_module_text()
  when declared(init_module_wasm_engine): init_module_wasm_engine()
  when declared(init_module_plugin_system_wasm): init_module_plugin_system_wasm()
  when declared(init_module_unsaved_saver): init_module_unsaved_saver()
  when declared(init_module_language_server_document_completion): init_module_language_server_document_completion()
  when declared(init_module_undo_tree): init_module_undo_tree()
  when declared(init_module_language_server_paths): init_module_language_server_paths()
  when declared(init_module_angelscript_formatter): init_module_angelscript_formatter()
  when declared(init_module_debugger): init_module_debugger()
  when declared(init_module_dashboard): init_module_dashboard()
  when declared(init_module_vcs_git): init_module_vcs_git()
  when declared(init_module_vcs_perforce): init_module_vcs_perforce()
  when declared(init_module_vim): init_module_vim()
  when declared(init_module_language_server_ctags): init_module_language_server_ctags()
  when declared(init_module_log): init_module_log()
  when declared(init_module_language_server_lsp): init_module_language_server_lsp()
  when declared(init_module_language_server_regex): init_module_language_server_regex()
  when declared(init_module_language_server_ue_as): init_module_language_server_ue_as()
  when declared(init_module_language_server_ue_cpp): init_module_language_server_ue_cpp()
  when declared(init_module_lsp_server): init_module_lsp_server()
  when declared(init_module_log_terminal): init_module_log_terminal()
  when declared(init_module_gui_platform): init_module_gui_platform()
  when declared(init_module_markdown_component): init_module_markdown_component()
  when declared(init_module_git_ui): init_module_git_ui()

proc shutdownModules*() =
  when declared(shutdown_module_git_ui): shutdown_module_git_ui()
  when declared(shutdown_module_markdown_component): shutdown_module_markdown_component()
  when declared(shutdown_module_gui_platform): shutdown_module_gui_platform()
  when declared(shutdown_module_log_terminal): shutdown_module_log_terminal()
  when declared(shutdown_module_lsp_server): shutdown_module_lsp_server()
  when declared(shutdown_module_language_server_ue_cpp): shutdown_module_language_server_ue_cpp()
  when declared(shutdown_module_language_server_ue_as): shutdown_module_language_server_ue_as()
  when declared(shutdown_module_language_server_regex): shutdown_module_language_server_regex()
  when declared(shutdown_module_language_server_lsp): shutdown_module_language_server_lsp()
  when declared(shutdown_module_log): shutdown_module_log()
  when declared(shutdown_module_language_server_ctags): shutdown_module_language_server_ctags()
  when declared(shutdown_module_vim): shutdown_module_vim()
  when declared(shutdown_module_vcs_perforce): shutdown_module_vcs_perforce()
  when declared(shutdown_module_vcs_git): shutdown_module_vcs_git()
  when declared(shutdown_module_dashboard): shutdown_module_dashboard()
  when declared(shutdown_module_debugger): shutdown_module_debugger()
  when declared(shutdown_module_angelscript_formatter): shutdown_module_angelscript_formatter()
  when declared(shutdown_module_language_server_paths): shutdown_module_language_server_paths()
  when declared(shutdown_module_undo_tree): shutdown_module_undo_tree()
  when declared(shutdown_module_language_server_document_completion): shutdown_module_language_server_document_completion()
  when declared(shutdown_module_unsaved_saver): shutdown_module_unsaved_saver()
  when declared(shutdown_module_plugin_system_wasm): shutdown_module_plugin_system_wasm()
  when declared(shutdown_module_wasm_engine): shutdown_module_wasm_engine()
  when declared(shutdown_module_text): shutdown_module_text()
  when declared(shutdown_module_move_database): shutdown_module_move_database()
  when declared(shutdown_module_search_component): shutdown_module_search_component()
  when declared(shutdown_module_command_line): shutdown_module_command_line()
  when declared(shutdown_module_event_service): shutdown_module_event_service()
  when declared(shutdown_module_decoration_component): shutdown_module_decoration_component()
  when declared(shutdown_module_workspace_edit): shutdown_module_workspace_edit()
  when declared(shutdown_module_contextline_component): shutdown_module_contextline_component()
  when declared(shutdown_module_treesitter_component): shutdown_module_treesitter_component()
  when declared(shutdown_module_snippet_component): shutdown_module_snippet_component()
  when declared(shutdown_module_hover_component): shutdown_module_hover_component()
  when declared(shutdown_module_command_component): shutdown_module_command_component()
  when declared(shutdown_module_formatting_component): shutdown_module_formatting_component()
  when declared(shutdown_module_terminal): shutdown_module_terminal()
  when declared(shutdown_module_plugin_service): shutdown_module_plugin_service()
  when declared(shutdown_module_stats): shutdown_module_stats()
  when declared(shutdown_module_command_server): shutdown_module_command_server()
  when declared(shutdown_module_layout): shutdown_module_layout()
  when declared(shutdown_module_command_service): shutdown_module_command_service()
  when declared(shutdown_module_register): shutdown_module_register()
  when declared(shutdown_module_text_editor_component): shutdown_module_text_editor_component()
  when declared(shutdown_module_status_line): shutdown_module_status_line()
  when declared(shutdown_module_terminal_platform): shutdown_module_terminal_platform()

proc loadModulesDynamically*(loadModule: proc(name: string) {.raises: [].}) =
  loadModule("terminal_platform")
  loadModule("status_line")
  loadModule("text_editor_component")
  loadModule("register")
  loadModule("command_service")
  loadModule("layout")
  loadModule("command_server")
  loadModule("stats")
  loadModule("plugin_service")
  loadModule("terminal")
  loadModule("formatting_component")
  loadModule("command_component")
  loadModule("hover_component")
  loadModule("snippet_component")
  loadModule("treesitter_component")
  loadModule("contextline_component")
  loadModule("workspace_edit")
  loadModule("decoration_component")
  loadModule("event_service")
  loadModule("command_line")
  loadModule("search_component")
  loadModule("move_database")
  loadModule("text")
  loadModule("wasm_engine")
  loadModule("plugin_system_wasm")
  loadModule("unsaved_saver")
  loadModule("language_server_document_completion")
  loadModule("undo_tree")
  loadModule("language_server_paths")
  loadModule("angelscript_formatter")
  loadModule("debugger")
  loadModule("dashboard")
  loadModule("vcs_git")
  loadModule("vcs_perforce")
  loadModule("vim")
  loadModule("language_server_ctags")
  loadModule("log")
  loadModule("language_server_lsp")
  loadModule("language_server_regex")
  loadModule("language_server_ue_as")
  loadModule("language_server_ue_cpp")
  loadModule("lsp_server")
  loadModule("log_terminal")
  loadModule("gui_platform")
  loadModule("markdown_component")
  loadModule("git_ui")
