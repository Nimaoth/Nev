(
  (context vfs)

  (inject self VFSService "getServiceChecked(VFSService)")

  (command mountVfs [(parentPath "Option[string]") (prefix string) (config JsonNode)] () "")
  (command normalizePath [(path string)] string "")
  (command localizePath [(path string)] string "")
  (command writeFileSync [(path string) (content string)] () "")
  (command readFileSync [(path string)] string "")
  (command deleteFileSync [(path string)] () "")
  (command genTempPath [(prefix string) (suffix string) (dir string "temp://") (randLen int 8) (checkExists bool true)] string "")
)