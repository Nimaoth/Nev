(
  (context sdl)

  (inject self SdlPlatform "getSdlPlatform()")

  (command screenshot sdlScreenshot [(path string "")] string "
    Save the next rendered frame as a PNG and return its path.
    Defaults to screenshots/screenshot-<timestamp>.png (relative to the working directory).")
  (command startRecording sdlStartRecording [(dir string "") (seconds float 0) (maxFrames int 0)] string "
    Save every rendered frame as a PNG into `dir` until stop-recording is run, or
    `seconds`/`maxFrames` is reached (0 = unlimited). Returns the directory.
    Defaults to screenshots/recording-<timestamp>. Frames are only rendered when
    something changes; index.txt lists each frame with its time since the start.")
  (command stopRecording sdlStopRecording [] string "
    Stop the current recording and return its directory.")
)
