(
  (context plugins)

  (inject self PluginServiceImpl "getServiceChecked(PluginServiceImpl)")

  (command bindKeys [(context string) (subContext string) (keys string) (action string) (arg string "") (description string "") (source "tuple[filename: string, line: int, column: int]" ("(\"\", 0, 0)"))] () "")
)