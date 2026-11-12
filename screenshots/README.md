# Documentation captures

Build the runner from the repository root:

```powershell
nim c -d:release --undef:useDynlib -o:tools\screenshot_scenarios.exe tools\screenshot_scenarios.nim
```

The runner is standalone; `--undef:useDynlib` prevents it from importing Nev's
dynamic runtime, which can fail at startup with `could not import: roots`.

Run all scenarios, or select names:

```powershell
.\tools\screenshot_scenarios.exe --list
.\tools\screenshot_scenarios.exe --gif
.\tools\screenshot_scenarios.exe --gif markdown-header-hiding lsp_completions
```

All screenshots and GIFs are written directly into `../NevScreenshots`.
Names come from the `screenshot` and `start-recording` steps, so they must be
unique across scenarios. Rerunning a scenario replaces only its named outputs.
The original top-level documentation images are replaced by their new captures.
Use `--out:DIR` for a separate review folder.

With `--gif`, frame PNGs are kept in the temporary control directory until
ffmpeg successfully produces the GIF, then deleted. Timing/drop metadata
remains in that temporary directory. Conversion failures retain the frames.
Without `--gif`, frames are published directly into the output folder as
`<recording>-frame-000000.png`, alongside `<recording>.index.txt` and
`<recording>.ffconcat`.

## Scenarios and fixtures

Each folder in [scenarios](scenarios) contains `scenario.json` and new example
files created specifically for documentation, not files from the original
screenshots. The `source-media` property identifies the original image or GIF.
Every run copies the fixture folder into a fresh temporary workspace and starts
a new SDL editor instance with user configuration and mouse input disabled.

The `setup` array contains external command arrays run synchronously in that
copied workspace before launching the editor. Nonzero exit codes fail the
scenario. Setup is not allowed with an in-place `workspace` override.
Git scenarios create a local disposable repository with an example baseline;
they never modify the editor repository or use its history.

External tools required:

- `ffmpeg` for `--gif`.
- `git` for `git`, `git_changed_files` and `git_diff`.
- `clangd` for the four `lsp*` scenarios. These use small C programs; the
  diagnostics example deliberately contains a type error.
- `clang` and LLVM 18's `lldb-dap` for `debug`. Its scenario currently points
  to the local LLVM 18 installation; update the adapter path for another machine.

The complete format is documented in
[screenshot_scenarios.nim](../tools/screenshot_scenarios.nim).
Editor actions need a leading dot, e.g. `.get-completions`, `.set-config`,
`.markdown.toggle-bold`. Key names are uppercase, e.g. `<ESCAPE>` and `<DOWN>`.

No scenarios are created for `markdown-inline-images.png`,
`markdown-animated-gif.gif`, or `markdown-animated-gif2.gif`: Markdown image
embedding is not implemented yet. `graph.png` is a static VFS architecture
diagram, not an editor capture, and is intentionally left unchanged.
