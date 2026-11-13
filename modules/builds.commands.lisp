(
  (context builds)

  (inject view BuildsView "getBuildsView()")

  (command toggle buildsToggle [] () "Show or hide the builds view")
  (command run buildsRun [(name string "")] () "Run the build or run configuration `name` configured in `builds`. Reruns it if it is already running.")
  (command stop buildsStop [(name string "")] () "Stop the build `name`. The first call sends Ctrl+C, the second one kills the process. Stops all running builds if `name` is empty.")
  (command rerun-last buildsRerunLast [] () "Run the last started build again")
  (command show-terminal buildsShowTerminal [(name string "")] () "Show the terminal of the build `name`, or the last started build if `name` is empty")
  (command choose buildsChoose [] () "Choose a build to run from a list")
)
