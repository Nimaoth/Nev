include abs

proc handleAction*(action: string, arg: string): bool =
  log "[script] ", action, ", ", arg

  case action
  else: return false

  return true

addCommand "editor", "<ESCAPE>", "escape"
addCommand "editor", "<C-l><C-h>", "change-font-size", "-1"
addCommand "editor", "<C-l><C-f>", "change-font-size", "1"
addCommand "editor", "<C-g>", "toggle-status-bar-location"
addCommand "editor", "<C-l><C-n>", "set-layout horizontal"
addCommand "editor", "<C-l><C-r>", "set-layout vertical"
addCommand "editor", "<C-l><C-t>", "set-layout fibonacci"
addCommand "editor", "<CA-h>", "change-layout-prop main-split", "-0.05"
addCommand "editor", "<CA-f>", "change-layout-prop main-split", "+0.05"
addCommand "editor", "<CA-v>", "create-view"
addCommand "editor", "<CA-a>", "create-keybind-autocomplete-view"
addCommand "editor", "<CA-x>", "close-view"
addCommand "editor", "<CA-n>", "prev-view"
addCommand "editor", "<CA-t>", "next-view"
addCommand "editor", "<CS-n>", "move-view-prev"
addCommand "editor", "<CS-t>", "move-view-next"
addCommand "editor", "<CA-r>", "move-current-view-to-top"
addCommand "editor", "<C-s>", "write-file"
addCommand "editor", "<CS-r>", "load-file"
addCommand "editor", "<C-p>", "command-line"
addCommand "editor", "<C-l>tt", "choose-theme"

addCommand "commandLine", "<ESCAPE>", "exit-command-line"
addCommand "commandLine", "<ENTER>", "execute-command-line"
addCommand "commandLine", "<BACKSPACE>", "backspace"
addCommand "commandLine", "<DELETE>", "delete"
addCommand "commandLine", "<SPACE>", "insert", " "

proc postInitialize*() =
  log "[script] postInitialize()"

