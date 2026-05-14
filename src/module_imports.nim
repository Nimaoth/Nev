when not defined(useDynlib):
  import "../modules/theme.nim"
  import "../modules/lisp.nim"
  import "../modules/input_handler/input_handler.nim"
  import "../modules/terminal_platform/terminal_platform.nim"
  import "../modules/vfs_config.nim"
  import "../modules/vfs_local.nim"
  import "../modules/vfs_service.nim"
  import "../modules/event_service.nim"
  import "../modules/session.nim"
  import "../modules/status_line.nim"
  import "../modules/workspace.nim"
  import "../modules/log.nim"
  import "../modules/wasm_engine.nim"
  import "../modules/treesitter/treesitter.nim"
  import "../modules/register.nim"
  import "../modules/command_service.nim"
  import "../modules/move_database.nim"
  import "../modules/move_component.nim"
  import "../modules/text_component.nim"
  import "../modules/text_editor_component.nim"
  import "../modules/layout/layout.nim"
  import "../modules/command_server.nim"
  import "../modules/stats.nim"
  import "../modules/plugin_service.nim"
  import "../modules/command_component.nim"
  import "../modules/file_previewer.nim"
  import "../modules/decoration_component.nim"
  import "../modules/language_server_list.nim"
  import "../modules/language_server_component.nim"
  import "../modules/language_server_command_line.nim"
  import "../modules/command_line.nim"
  import "../modules/search_component.nim"
  import "../modules/selector_popup/selector_popup.nim"
  import "../modules/terminal/terminal.nim"
  import "../modules/completion.nim"
  import "../modules/completion_provider_snippet.nim"
  import "../modules/hover_component.nim"
  import "../modules/completion_provider_lsp.nim"
  import "../modules/treesitter_component.nim"
  import "../modules/contextline_component.nim"
  import "../modules/workspace_edit.nim"
  import "../modules/snippet_component.nim"
  import "../modules/inlay_hint_component.nim"
  import "../modules/formatting_component.nim"
  import "../modules/toast.nim"
  import "../modules/completion_provider_document.nim"
  import "../modules/text/text.nim"
  import "../modules/render_view.nim"
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
  import "../modules/language_server_regex.nim"
  import "../modules/language_server_lsp/language_server_lsp.nim"
  import "../modules/language_server_ue_cpp.nim"
  import "../modules/language_server_ue_as.nim"
  import "../modules/lsp_server.nim"
  import "../modules/log_terminal.nim"
  import "../modules/gui_platform/gui_platform.nim"
  import "../modules/markdown_component.nim"
  import "../modules/vcs_commands.nim"
  import "../modules/git_ui.nim"

proc initModules*() =
  when declared(init_module_theme): init_module_theme()
  when declared(init_module_lisp): init_module_lisp()
  when declared(init_module_input_handler): init_module_input_handler()
  when declared(init_module_terminal_platform): init_module_terminal_platform()
  when declared(init_module_vfs_config): init_module_vfs_config()
  when declared(init_module_vfs_local): init_module_vfs_local()
  when declared(init_module_vfs_service): init_module_vfs_service()
  when declared(init_module_event_service): init_module_event_service()
  when declared(init_module_session): init_module_session()
  when declared(init_module_status_line): init_module_status_line()
  when declared(init_module_workspace): init_module_workspace()
  when declared(init_module_log): init_module_log()
  when declared(init_module_wasm_engine): init_module_wasm_engine()
  when declared(init_module_treesitter): init_module_treesitter()
  when declared(init_module_register): init_module_register()
  when declared(init_module_command_service): init_module_command_service()
  when declared(init_module_move_database): init_module_move_database()
  when declared(init_module_move_component): init_module_move_component()
  when declared(init_module_text_component): init_module_text_component()
  when declared(init_module_text_editor_component): init_module_text_editor_component()
  when declared(init_module_layout): init_module_layout()
  when declared(init_module_command_server): init_module_command_server()
  when declared(init_module_stats): init_module_stats()
  when declared(init_module_plugin_service): init_module_plugin_service()
  when declared(init_module_command_component): init_module_command_component()
  when declared(init_module_file_previewer): init_module_file_previewer()
  when declared(init_module_decoration_component): init_module_decoration_component()
  when declared(init_module_language_server_list): init_module_language_server_list()
  when declared(init_module_language_server_component): init_module_language_server_component()
  when declared(init_module_language_server_command_line): init_module_language_server_command_line()
  when declared(init_module_command_line): init_module_command_line()
  when declared(init_module_search_component): init_module_search_component()
  when declared(init_module_selector_popup): init_module_selector_popup()
  when declared(init_module_terminal): init_module_terminal()
  when declared(init_module_completion): init_module_completion()
  when declared(init_module_completion_provider_snippet): init_module_completion_provider_snippet()
  when declared(init_module_hover_component): init_module_hover_component()
  when declared(init_module_completion_provider_lsp): init_module_completion_provider_lsp()
  when declared(init_module_treesitter_component): init_module_treesitter_component()
  when declared(init_module_contextline_component): init_module_contextline_component()
  when declared(init_module_workspace_edit): init_module_workspace_edit()
  when declared(init_module_snippet_component): init_module_snippet_component()
  when declared(init_module_inlay_hint_component): init_module_inlay_hint_component()
  when declared(init_module_formatting_component): init_module_formatting_component()
  when declared(init_module_toast): init_module_toast()
  when declared(init_module_completion_provider_document): init_module_completion_provider_document()
  when declared(init_module_text): init_module_text()
  when declared(init_module_render_view): init_module_render_view()
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
  when declared(init_module_language_server_regex): init_module_language_server_regex()
  when declared(init_module_language_server_lsp): init_module_language_server_lsp()
  when declared(init_module_language_server_ue_cpp): init_module_language_server_ue_cpp()
  when declared(init_module_language_server_ue_as): init_module_language_server_ue_as()
  when declared(init_module_lsp_server): init_module_lsp_server()
  when declared(init_module_log_terminal): init_module_log_terminal()
  when declared(init_module_gui_platform): init_module_gui_platform()
  when declared(init_module_markdown_component): init_module_markdown_component()
  when declared(init_module_vcs_commands): init_module_vcs_commands()
  when declared(init_module_git_ui): init_module_git_ui()

proc shutdownModules*() =
  when declared(shutdown_module_git_ui): shutdown_module_git_ui()
  when declared(shutdown_module_vcs_commands): shutdown_module_vcs_commands()
  when declared(shutdown_module_markdown_component): shutdown_module_markdown_component()
  when declared(shutdown_module_gui_platform): shutdown_module_gui_platform()
  when declared(shutdown_module_log_terminal): shutdown_module_log_terminal()
  when declared(shutdown_module_lsp_server): shutdown_module_lsp_server()
  when declared(shutdown_module_language_server_ue_as): shutdown_module_language_server_ue_as()
  when declared(shutdown_module_language_server_ue_cpp): shutdown_module_language_server_ue_cpp()
  when declared(shutdown_module_language_server_lsp): shutdown_module_language_server_lsp()
  when declared(shutdown_module_language_server_regex): shutdown_module_language_server_regex()
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
  when declared(shutdown_module_render_view): shutdown_module_render_view()
  when declared(shutdown_module_text): shutdown_module_text()
  when declared(shutdown_module_completion_provider_document): shutdown_module_completion_provider_document()
  when declared(shutdown_module_toast): shutdown_module_toast()
  when declared(shutdown_module_formatting_component): shutdown_module_formatting_component()
  when declared(shutdown_module_inlay_hint_component): shutdown_module_inlay_hint_component()
  when declared(shutdown_module_snippet_component): shutdown_module_snippet_component()
  when declared(shutdown_module_workspace_edit): shutdown_module_workspace_edit()
  when declared(shutdown_module_contextline_component): shutdown_module_contextline_component()
  when declared(shutdown_module_treesitter_component): shutdown_module_treesitter_component()
  when declared(shutdown_module_completion_provider_lsp): shutdown_module_completion_provider_lsp()
  when declared(shutdown_module_hover_component): shutdown_module_hover_component()
  when declared(shutdown_module_completion_provider_snippet): shutdown_module_completion_provider_snippet()
  when declared(shutdown_module_completion): shutdown_module_completion()
  when declared(shutdown_module_terminal): shutdown_module_terminal()
  when declared(shutdown_module_selector_popup): shutdown_module_selector_popup()
  when declared(shutdown_module_search_component): shutdown_module_search_component()
  when declared(shutdown_module_command_line): shutdown_module_command_line()
  when declared(shutdown_module_language_server_command_line): shutdown_module_language_server_command_line()
  when declared(shutdown_module_language_server_component): shutdown_module_language_server_component()
  when declared(shutdown_module_language_server_list): shutdown_module_language_server_list()
  when declared(shutdown_module_decoration_component): shutdown_module_decoration_component()
  when declared(shutdown_module_file_previewer): shutdown_module_file_previewer()
  when declared(shutdown_module_command_component): shutdown_module_command_component()
  when declared(shutdown_module_plugin_service): shutdown_module_plugin_service()
  when declared(shutdown_module_stats): shutdown_module_stats()
  when declared(shutdown_module_command_server): shutdown_module_command_server()
  when declared(shutdown_module_layout): shutdown_module_layout()
  when declared(shutdown_module_text_editor_component): shutdown_module_text_editor_component()
  when declared(shutdown_module_text_component): shutdown_module_text_component()
  when declared(shutdown_module_move_component): shutdown_module_move_component()
  when declared(shutdown_module_move_database): shutdown_module_move_database()
  when declared(shutdown_module_command_service): shutdown_module_command_service()
  when declared(shutdown_module_register): shutdown_module_register()
  when declared(shutdown_module_treesitter): shutdown_module_treesitter()
  when declared(shutdown_module_wasm_engine): shutdown_module_wasm_engine()
  when declared(shutdown_module_log): shutdown_module_log()
  when declared(shutdown_module_workspace): shutdown_module_workspace()
  when declared(shutdown_module_status_line): shutdown_module_status_line()
  when declared(shutdown_module_session): shutdown_module_session()
  when declared(shutdown_module_event_service): shutdown_module_event_service()
  when declared(shutdown_module_vfs_service): shutdown_module_vfs_service()
  when declared(shutdown_module_vfs_local): shutdown_module_vfs_local()
  when declared(shutdown_module_vfs_config): shutdown_module_vfs_config()
  when declared(shutdown_module_terminal_platform): shutdown_module_terminal_platform()
  when declared(shutdown_module_input_handler): shutdown_module_input_handler()
  when declared(shutdown_module_lisp): shutdown_module_lisp()
  when declared(shutdown_module_theme): shutdown_module_theme()

proc loadModulesDynamically*(loadModule: proc(name: string) {.raises: [].}) =
  loadModule("theme")
  loadModule("lisp")
  loadModule("input_handler")
  loadModule("terminal_platform")
  loadModule("vfs_config")
  loadModule("vfs_local")
  loadModule("vfs_service")
  loadModule("event_service")
  loadModule("session")
  loadModule("status_line")
  loadModule("workspace")
  loadModule("log")
  loadModule("wasm_engine")
  loadModule("treesitter")
  loadModule("register")
  loadModule("command_service")
  loadModule("move_database")
  loadModule("move_component")
  loadModule("text_component")
  loadModule("text_editor_component")
  loadModule("layout")
  loadModule("command_server")
  loadModule("stats")
  loadModule("plugin_service")
  loadModule("command_component")
  loadModule("file_previewer")
  loadModule("decoration_component")
  loadModule("language_server_list")
  loadModule("language_server_component")
  loadModule("language_server_command_line")
  loadModule("command_line")
  loadModule("search_component")
  loadModule("selector_popup")
  loadModule("terminal")
  loadModule("completion")
  loadModule("completion_provider_snippet")
  loadModule("hover_component")
  loadModule("completion_provider_lsp")
  loadModule("treesitter_component")
  loadModule("contextline_component")
  loadModule("workspace_edit")
  loadModule("snippet_component")
  loadModule("inlay_hint_component")
  loadModule("formatting_component")
  loadModule("toast")
  loadModule("completion_provider_document")
  loadModule("text")
  loadModule("render_view")
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
  loadModule("language_server_regex")
  loadModule("language_server_lsp")
  loadModule("language_server_ue_cpp")
  loadModule("language_server_ue_as")
  loadModule("lsp_server")
  loadModule("log_terminal")
  loadModule("gui_platform")
  loadModule("markdown_component")
  loadModule("vcs_commands")
  loadModule("git_ui")
