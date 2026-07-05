(
  (context profiler)

  (inject view ProfilerView "getProfiler()")

  (command toggle profilerToggle [] () "Toggle Profiler UI")
  (command graph profilerGraph [(arg string "")] () "Dump allocation graph for pointer argument")
)