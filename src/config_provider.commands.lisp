(
  (context config)

  (inject self ConfigService "getServiceChecked(ConfigService)")

  (command logOptions [] () "")
  (command setOption [(option string) (value JsonNode) (override bool true)] () "")
  (command cycleOption [(path string) (values JsonNode)] () "")
  (command getOptionJson [(path string) (default JsonNode ("newJNull()"))] JsonNode "")
  (command getFlag [(flag string) (default bool false)] bool "")
  (command setFlag [(flag string) (value bool)] () "")
  (command toggleFlag [(flag string)] () "")
)