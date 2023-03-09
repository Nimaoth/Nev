
const exposeScriptingApi* {.booldefine.}: bool = false
const enableGui* {.booldefine.}: bool = false
const enableTerminal* {.booldefine.}: bool = false
const enableTableIdCacheChecking* {.booldefine.}: bool = false

when not defined(js):
  when not enableGui and not enableTerminal:
    {.error: "No backend enabled".}