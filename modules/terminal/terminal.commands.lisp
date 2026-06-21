(
  (context terminal)

  (inject self TerminalServiceImpl "getServiceChecked(TerminalServiceImpl)")

  (command create createTerminal [(command string "") (options CreateTerminalOptions ("CreateTerminalOptions()"))] () "")
  (command run runInTerminal [(shell string) (command string) (options RunInTerminalOptions ("RunInTerminalOptions()"))] () "")
  (command sendTerminalInput [(input string) (noKitty bool false)] () "")
  (command sendTerminalInputAndSetMode [(input string) (mode string)] () "")
  (command setTerminalMode [(mode string)] () "")
  (command escape [] () "")
  (command scroll [(amount int)] () "")
  (command select selectTerminal [(preview bool true) (scaleX float 0.9) (scaleY float 0.9) (previewScale float 0.6)] () "")
  (command editTerminalBuffer [] () "")
  (command paste pasteTerminal [(register string "")] () "")

)