(
  (context session)

  (inject self SessionService "getServiceChecked(SessionService)")

  (command setSessionDataJson [(path string) (value JsonNode) (override bool true)] () "")
  (command getSessionDataJson [(path string) (default JsonNode)] JsonNode "")
)