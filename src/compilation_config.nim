
const exposeScriptingApi* {.booldefine.}: bool = false
const enableGui* {.booldefine.}: bool = false
const enableTerminal* {.booldefine.}: bool = false

when not enableGui and not enableTerminal:
  {.error: "No backend enabled".}