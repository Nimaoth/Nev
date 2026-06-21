(
  (inject self App "({.gcsafe.}: gApp)")

  (command reapplyConfigKeybindings [(app bool false) (home bool false) (workspace bool false) (wait bool false)] () "
    Reapply keybindings from config files")

  (command loadSession [(path string)] () "")
  (command runExternalCommand [(command string) (args "seq[string]" []) (workingDir string "")] () "")
  (command disableLogFrameTime [(disable bool)] () "")
  (command enableDebugPrintAsyncAwaitStackTrace [(enable bool)] () "")
  (command toggleShowDrawnNodes [] () "")
  (command saveAppState [] () "")
  (command requestRender [(redrawEverything bool false)] () "")
  (command quit [] () "")
  (command quitImmediately [(exitCode int 0)] () "")
  (command help [(about string "")] () "")
  (command changeFontSize [(amount float32)] () "")
  (command changeLineDistance [(amount float32)] () "")
  (command toggleStatusBarLocation [] () "")
  (command logs [(slot string "")] () "")
  (command toggleConsoleLogger [] () "")
  (command writeFile [(path string "")] () "")
  (command loadFile [(path string "")] () "")
  (command loadTheme [(name string) (force bool false)] () "")
  (command openSession [(newWindow bool false) (root string "home://") (preview bool true) (scaleX float 0.9) (scaleY float 0.8) (previewScale float 0.4)] () "")
  (command openRecentSession [(preview bool true) (scaleX float 0.9) (scaleY float 0.8) (previewScale float 0.4)] () "")
  (command chooseTheme [] () "")
  (command crash [(message string "")] () "This command will cause the editor to crash by failing an assertion.")
  (command crash2 [] () "This command will cause the editor to crash by accessing a nil reference.")
  (command createFile [(path string)] () "")
  (command recomputeWorkspaceCache [] () "")
  (command reloadWorkspaceIgnore [] () "")
  (command browseKeybinds [(preview bool true) (scaleX float 0.9) (scaleY float 0.8) (previewScale float 0.4) (slot string "")] () "")
  (command browseSettings [(includeActiveEditor bool false) (scaleX float 0.8) (scaleY float 0.8) (previewScale float 0.5) (slot string "")] () "")
  (command chooseFile [(preview bool true) (scaleX float 0.8) (scaleY float 0.8) (previewScale float 0.5) (slot string "")] () "
    Opens a file dialog which shows all files in the currently open workspaces
    Press <ENTER> to select a file
    Press <ESCAPE> to close the dialogue")
  (command chooseOpenDocument [(slot string "")] () "")
  (command showPlugins [(scaleX float 0.9) (scaleY float 0.9) (previewScale float 0.6) (slot string "")] () "")
  (command gotoNextLocation [] () "")
  (command gotoPrevLocation [] () "")
  (command chooseLocation [(slot string "")] () "")
  (command searchGlobalInteractive [(path string "") (slot string "")] () "")
  (command searchGlobal [(query string) (slot string "")] () "")
  (command installTreesitterParser [(language string) (host string "github.com")] () "
    Install a treesitter parser by downloading the repository and building a wasm module.
    `language` can either be a language id (`nim`, `cpp`, `markdown`, etc), `<username>/<repository>`
    or `<username>/<repository>/<some/path>`.

    todo: copy queries to `languages/<language>/queries`

    If you specify a language id then the repository name will be read from the setting
    `languages.<language>.treesitter`

    The repository will be cloned in `<installdir>/languages/<repository>`.

    ## Requirements:
    - `git`
    - `tree-sitter-cli` (`npm install tree-sitter-cli` or `cargo install tree-sitter-cli`)
    All required programs need to be in `PATH`.

    ## Example:
    - Assuming `languages.cpp.treesitter` is set to \"tree-sitter/tree-sitter-cpp\"
    - `install-treesitter-parser \"cpp\"` will clone/pull the repository
      `https://github.com/tree-sitter/tree-sitter-cpp` and then build the parser
    - `install-treesitter-parser \"tree-sitter/tree-sitter-ocaml/grammars/ocaml\"` will clone/pull
      the repository `https://github.com/tree-sitter/tree-sitter-ocaml` and then build the parser from
      the directory `<installdir>/languages/tree-sitter-ocaml/grammars/ocaml`")
  (command installTreesitterParserPrebuilt [(language string)] () "
    Install a treesitter parser by downloading a prebuilt wasm binary from `https://github.com/Nimaoth/tree-sitter-wasm-binaries/releases/tag/v0.3`")
  (command installTreesitterParserPrebuiltFromList [] () "
    Install a treesitter parser by downloading a prebuilt wasm binary from `https://github.com/Nimaoth/tree-sitter-wasm-binaries/releases/tag/v0.3`")
  (command exploreFiles [(root string "") (showVFS bool false) (normalize bool true) (diff bool false) (previewScale float 0.5) (slot string "")] () "
    Open a file explorer at `root`. If `diff` is true then files will be show as a diff if applicable")
  (command exploreWorkspacePrimary [] () "")
  (command exploreCurrentFileDirectory [] () "")
  (command reloadConfig [(clearOptions bool false)] () "
    Reloads settings.json and keybindings.json from the app directory, home directory and workspace")
  (command reloadTheme [] () "")
  (command currentFilePath [] string "")
  (command currentLocalFilePath [] string "")
  (command saveSession [(sessionFile string "")] () "
    Reloads some of the state stored in the session file (default: config/config.json)")
  (command dumpKeymapGraphViz [(context string "")] () "")
  (command setMode [(mode string)] () "")
  (command changeAnimationSpeed [(factor float)] () "")
  (command logRootNode [] () "")
  (command replayKeys [(register string)] () "")
  (command inputKeys [(input string)] () "")
  (command collectGarbage [] () "")
  (command echoArgs [(args JsonNode "" ...)] () "")
  (command all [(args JsonNode "" ...)] () "")
  (command printStatistics [] () "")

)