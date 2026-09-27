(
  (context file-explorer)

  (inject view FileExplorerView "getFileExplorerView()")

  (command toggle fileExplorerToggle [] () "Toggle the file explorer")
  (command refresh fileExplorerRefresh [] () "Refresh the file explorer")
)
