import dap_client, command_service
include generated/dap_client_commands

proc registerDapClientCommands*(commands: CommandService) =
  registerCommands(commands)
