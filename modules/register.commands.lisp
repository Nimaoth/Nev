(
  (context registers)

  (inject self Registers "getServiceChecked(Registers)")

  (command registersSetRegisterText [(text string) (register string "")] () "")
  (command registersGetRegisterText [(register string)] string "")
  (command startRecordingKeys [(register string)] () "")
  (command stopRecordingKeys [(register string)] () "")
  (command startRecordingCommands [(register string)] () "")
  (command stopRecordingCommands [(register string)] () "")
  (command isReplayingCommands [] bool "")
  (command isReplayingKeys [] bool "")
  (command isRecordingCommands [(registry string)] bool "")
)