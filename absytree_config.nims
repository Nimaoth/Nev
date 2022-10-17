echo "Hello from config"

runAction "create-view", ""

proc handleAction*(action: string, arg: string): bool =
  echo "[script] ", action, ", ", arg

  return true