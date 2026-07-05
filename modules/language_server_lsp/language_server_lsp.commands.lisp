(
  (context lsp)

  (command lspLogVerbose [(val bool)] () "")
  (command lspToggleLogServerDebug [] () "")
  (command lspLogServerDebug [(val bool)] () "")

  (inject self LanguageServerLspService "getServiceChecked(LanguageServerLspService)")

  (command list listLanguageServers [] () "List all language servers (excluding builtins)")
)
