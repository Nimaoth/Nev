(
  (context lsp-server)

  (inject self LspServerService "getServiceChecked(LspServerService)")

  (command start lspServerStart [] () "Start LSP server, reading from stdin")
)