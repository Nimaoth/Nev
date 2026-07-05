(
  (context commands)

  (inject self CommandLineService "getServiceChecked(CommandLineService)")

  (command commandLine [(initialValue string "") (prefix string "")] () "")
  (command exitCommandLine [] () "")
  (command commandLineResult [(value string) (showInCommandLine bool false) (appendAndShowInFile bool false) (filename string "ed://.shell-command-results")] () "")
  (command clearCommandLineResults [] () "")
  (command executeCommandLine [] bool "")
  (command selectPreviousCommandInHistory [] () "")
  (command selectNextCommandInHistory [] () "")
  (command runShellCommand [(options RunShellCommandOptions ("RunShellCommandOptions()"))] () "")
  (command replayCommands [(register string)] () "")
)