(
  (context process)

  (inject self PluginService "getServiceChecked(PluginService)")

  (command runProcess [(process string) (args "seq[string]") (workingDir "Option[string]" string.none) (eval bool false)] () "")
)