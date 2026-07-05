(
  (context events)

  (inject self EventHandlerService "getServiceChecked(EventHandlerService)")

  (command setLeader [(leader string)] () "")
  (command setLeaders [(leaders "seq[string]")] () "")
  (command addLeader [(leader string)] () "")
  (command addLeaders [(leaders "seq[string]")] () "")
  (command clearCommands [(context string)] () "")
)