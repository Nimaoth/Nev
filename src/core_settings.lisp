(
  (enum SignColumnShowKind auto yes no number)

  (enum PluginCommandLoadBehaviour dont-run async-run wait-and-run async-or-wait)

  (enum FormatterInput temp-file file stdin)

  (enum IndentStyleKind tabs spaces)

  (enum ColorType hex float1 float255)

  (enum ScrollToChangeOnReload first last)

  (enum UnsavedBehaviour none temp real)

  (enum ToastStyle minimal box)

  (enum DiagnosticsLocation line-end below line-end-or-below)

  (group BackgroundSettings "ui.background"
    (setting transparent "bool" false
      "If true the background is transparent.")

    (setting inactive-brightness-change "float" -0.025
      "How much to change the brightness for inactive views."))

  (group ToastSettings "ui.toast"
    (setting style "ToastStyle" minimal
      "Animate toast positions")

    (setting duration "int" 8000
      "How long toasts are displayed for, in milliseconds.")

    (setting animation "bool" true
      "Animate toast positions")

    (setting max "int" 5
      "Max number of toast to show at a time"))

  (group UiSettings "ui"
    (setting theme "string" "app://themes/gruvbox-dark.json"
      "VFS path of the theme.")

    (setting font-family "string" "app://fonts/DejaVuSansMono.ttf"
      "Full path to regular font file.")

    (setting font-family-bold "string" "app://fonts/DejaVuSansMono-Bold.ttf"
      "Full path to bold font file.")

    (setting font-family-italic "string" "app://fonts/DejaVuSansMono-Oblique.ttf"
      "Full path to italic font file.")

    (setting font-family-bold-italic "string" "app://fonts/DejaVuSansMono-BoldOblique.ttf"
      "Full path to bold italic font file.")

    (setting which-key-delay "int" 250
      "After how many milliseconds the which key window opens.")

    (setting which-key-show-when-mod "bool" false
      "Show which key window when holding down modifiers.")

    (setting which-key-no-progress "bool" false
      "If true then the window showing next possible inputs will be displayed even when no keybinding is in progress (i.e. it will always be shown).")

    (setting which-key-height "int" 6
      "How many rows tall the window showing next possible inputs should be.")

    (setting popup-which-key-height "int" 5
      "How many rows tall the window showing next possible inputs should be when showing in a popup.")

    (setting max-views "int" 2
      "Maximum number of views (files or other UIs) which can be shown.")

    (setting syntax-highlighting "bool" true
      "Enable syntax highlighting.")

    (setting rainbow-parentheses "bool" false
      "Enable highlighting parentheses, brackets etc in different colors. Uses 'rainbow0', 'rainbow1' etc theme keys.")

    (setting indent-guide "bool" true
      "Enable indent guides to show the indentation of the current line.")

    (setting whitespace-char "string" "·"
      "Character to use when rendering whitespace. If this is the empty string or not set then spaces are not rendered.")

    (setting whitespace-color "string" "comment"
      "Color of rendered whitespace. Can be a theme key or hex color (e.g #ff00ff).")

    (setting scroll-speed "float" 50.0
      "How many pixels (or rows in the terminal) to scroll per scroll wheel tick.")

    (setting smooth-scroll "bool" true
      "Enable smooth scrolling.")

    (setting smooth-scroll-speed "float" 25.0
      "How fast smooth scrolling interpolates.")

    (setting smooth-scroll-snap-threshold "float" 0.5
      "Percentage of screen height at which the smooth scroll offset will be snapped to the target location.
E.g. if this is 0.5, then if the smooth scroll offset if further from the target scroll offset than 50% of the
screen height then the smooth scroll offset will instantly jump to the target scroll offset (-50% of the screen height).
This means that the smooth scrolling will not take time proportional to the scroll distance for jumps bigger than
the screen height.")

    (setting cursor-trail-speed "float" 100.0
      "How fast to interpolate the cursor trail position when moving the cursor. Higher means faster.")

    (setting cursor-trail-length "int" 2
      "How long the cursor trail is. Set to 0 to disable cursor trail.")

    (setting vsync "bool" true
      "Enable vertical sync to prevent screen tearing.")

    (setting line-numbers "LineNumbers" absolute
      "How line numbers should be displayed.")

    (setting diagnostics-location "DiagnosticsLocation" line-end
      "Where diagnostics are displayed relative to their source line.
'below' renders them on a separate line below.
'line-end' renders the first diagnostic inline at the end of the line.
'line-end-or-below' renders below on the cursor line, at line-end elsewhere (default).")

    (setting tab-header-width "int" 30
      "Width of tab layout headers in characters")

    (setting hide-tab-bar-when-single "bool" false
      "When true then tab layouts don't render a tab bar when they only have one tab.")

    (setting status-line "seq[JsonNodeEx]" ["mode" "layout" "vcs.status" "session"]
      "Configures what to show in the status line.")

    (setting scroll-bar "bool" true
      "Whether a scrollbar is shown.")

    (setting highlight-inline-changes "bool" true
      "Whether changes within a line should be highlighted in the diff view"))

  (group OpenSessionSettings "editor.open-session"
    (setting use-multiplexer "bool" true
      "If true then Nev will detect if it's running inside a multiplexer like tmux, zellij or wezterm (by using environment variables)
and if so opening a session will use the command `editor.open-session.tmux` or `editor.open-session.zellij` or `editor.open-session.wezterm`")

    (setting command "Option[string]" nil
      "Command to use when opening a session in a new window.")

    (setting args "Option[seq[JsonNodeEx]]" nil
      "Command arguments to use when opening a session in a new window."))

  (group GeneralSettings "editor"
    (setting save-in-session "bool" true
      "Any editor with this set to true will be stored in the session and restored on startup.")

    (setting close-unused-documents-timer "int" 10
      "How often the editor will check for unused documents and close them, in seconds.")

    (setting print-statistics-on-shutdown "bool" false
      "If true the editor prints memory usage statistics when quitting.")

    (setting max-search-results "int" 1000
      "Max number of search results returned by global text based search.")

    (setting max-search-result-display-len "int" 1000
      "Max length of each individual search result (search results are cut off after this value).")

    (setting custom-mode-on-top "bool" true
      "If true then the app mode event handler (if the app mode is not '') will be on top of the event handler stack,
otherwise it will be at the bottom (but still above the 'editor' event handler).")

    (setting clear-input-history-delay "int" 3000
      "After how many milliseconds of no input the input history is cleared.")

    (setting insert-input-delay "int" 150
      "After how many milliseconds of no input a pending input gets inserted as text, if you bind a key
which inserts text in e.g. a multi key keybinding aswell.
Say you bind `jj` to exit insert mode, then if you press `j` once and wait for this delay then it will
insert `j` into the document, but if you press `j` again it will will exit insert mode instead.
If you press another key like `k` before the time ends it will immediately insert the `j` and the `k`.")

    (setting record-input-history "bool" false
      "Whether the editor shows a history of the last few pressed buttons in the status bar.")

    (setting watch-theme "bool" true
      "Watch the theme directory for changes to the theme.")

    (setting watch-app-config "bool" true
      "Watch the config files in the app directory and automatically reload them when they change.")

    (setting watch-user-config "bool" true
      "Watch the config files in the user directory and automatically reload them when they change.")

    (setting watch-workspace-config "bool" true
      "Watch the config files in the workspace directory and automatically reload them when they change.")

    (setting keep-session-history "bool" true
      "If true then the editor will keep a history of opened sessions in data://sessions.json,
which enables features like opening a recent session or opening the last session.")

    (setting prompt-before-quit "bool" false
      "If true then you will be prompted to confirm quitting even when no unsaved changes exist.")

    (setting base-modes "seq[string]" ["editor"]
      "List of input modes which are always active (at the lowest priority).")

    (setting command-line-mode-high "string" "command-line-high"
      "Global mode to apply while the command line is open.")

    (setting command-line-mode-low "string" "command-line-low"
      "Global mode to apply while the command line is open.")

    (setting command-line-result-mode-high "string" "command-line-result-high"
      "Global mode to apply while the command line is open showing a command result.")

    (setting command-line-result-mode-low "string" "command-line-result-low"
      "Global mode to apply while the command line is open showing a command result.")

    (setting treesitter-wasm-download-url "string" "https://github.com/Nimaoth/tree-sitter-wasm-binaries/releases/download/v0.3/{language}.tar.gz"
      "Global mode to apply while the command line is open showing a command result."))

  (group TreesitterSettings "text.treesitter"
    (setting enable "bool" true
      "Enable parsing code into ASTs using treesitter. Also requires a treesitter parser for a specific language.")

    (setting path "Option[string]" nil
      "Override the path to the treesitter parser (.dll/.so/.wasm). By default")

    (setting language "Option[string]" nil
      "Override the language name used for choosing the treesitter parser. If not set then the documents language id is used.")

    (setting queries "Option[string]" nil
      "Path relative to the repository root where queries are located. If not set then the editor will look for the queries.")

    (setting repository "Option[string]" nil
      "Path relative to the repository root where queries are located. If not set then the editor will look for the queries."))

  (group SignColumnSettings "text.signs"
    (setting show "SignColumnShowKind" number
      "Defines how the sign column is displayed.
- auto: Signs are next to line numbers, width is based on amount of signs in a line.
- yes: Signs are next to line numbers and sign column is always visible. Width is defined in `max-width`
- no: Don't show the sign column
- number: Show signs instead of the line number, no extra sign column.")

    (setting max-width "int" 2
      "If `show` is `auto` then this is the max width of the sign column, if `show` is `yes` then this is the exact width."))

  (group MatchingWordHighlightSettings "text.highlight-matches"
    (setting enable "bool" true
      "Enable highlighting of text matching the current selection or word containing the cursor (if the selection is empty).")

    (setting delay "int" 250
      "How long after moving the cursor matching text is highlighted.")

    (setting max-selection-length "int" 1024
      "Don't highlight matching text if the selection spans more bytes than this.")

    (setting max-selection-lines "int" 5
      "Don't highlight matching text if the selection spans more lines than this.")

    (setting max-file-size "int" 104857600
      "Don't highlight matching text in files above this size (in bytes)."))

  (group HoverSettings "text.hover"
    (setting delay "int" 250
      "How many milliseconds after hovering a word the lsp hover request is sent.")

    (setting command "JsonNodeEx" nil
      "Command to run when hovering something."))

  (group InlayHintSettings "text.inlay-hints"
    (setting enable "bool" true
      "Whether inlay hints are enabled."))

  (group SearchRegexSettings "text.search-regexes"
    (setting show-only-matching-part "bool" true
      "If true then the search results will only show the part of a line that matched the regex.
If false then the entire line is shown.")

    (setting goto-definition "Option[RegexSetting]" nil
      "Regex to use when using the goto-definition feature.")

    (setting goto-declaration "Option[RegexSetting]" nil
      "Regex to use when using the goto-declaration feature.")

    (setting goto-type-definition "Option[RegexSetting]" nil
      "Regex to use when using the goto-type-definition feature.")

    (setting goto-implementation "Option[RegexSetting]" nil
      "Regex to use when using the goto-implementation feature.")

    (setting goto-references "Option[RegexSetting]" nil
      "Regex to use when using the goto-references feature.")

    (setting symbols "Option[RegexSetting]" nil
      "Regex to use when using the symbols feature.")

    (setting workspace-symbols "Option[RegexSetting]" nil
      "Regex to use when using the workspace-symbols feature.")

    (setting workspace-symbols-by-kind "Option[Table[string, RegexSetting]]" nil
      "Regex to use when using the workspace-symbols feature. Keys are LSP symbol kinds, values are the corresponding regex."))

  (group RipgrepSettings "text.ripgrep"
    (setting pass-type "bool" true
      "Pass the --type argument to ripgrep using either the language id or the value from `file-type`.")

    (setting file-type "Option[string]" nil
      "Override the ripgrep type name. By default the documents language id is used.")

    (setting extra-args "seq[string]" []
      "Extra arguments passed to ripgrep"))

  (group TrimTrailingWhitespaceSettings "text.trim-trailing-whitespace"
    (setting enabled "bool" true
      "If true trailing whitespace is deleted when saving files.")

    (setting max-size "int" 1000000
      "Don't trim trailing whitespace when filesize is above this limit."))

  (group IndentDetectionSettings "text.indent-detection"
    (setting enable "bool" true
      "Enable auto detecting the indent style when opening files.")

    (setting samples "int" 50
      "How many indent characters to process when detecting the indent style. Increase this if it fails for files which start with many unindented lines.")

    (setting timeout "int" 20
      "Max number of milliseconds to spend trying to detect the indent style."))

  (group DiffReloadSettings "text.diff-reload"
    (setting enable "bool" true
      "When reloading a file the editor will compute the diff between the file on disk and the in memory document,
and then apply the diff to the in memory version so it matches the content on disk.
This can reduce memory usage when reloading files often (although it increases memory usage while reloading and increases load times).
It's also better for collaboration as it doesn't affect the entire file.")

    (setting timeout "int" 250
      "Max number of milliseconds to use for diffing. If the timeout is exceeded then the file will be reloaded normally."))

  (group DiagnosticsSettings "text.diagnostics"
    (setting enable "bool" false
      "Enable diagnostics. Also requires a language server which supports diagnostics.")

    (setting snapshot-history "int" 5
      "How many snapshots to keep when editing. Snapshots are used to fix up diagnostic locations when receiving diagnostics
for an older version of the document (e.g when you continue editing and the languages doesn't respond fast enough).
You might want to increase this if you are using a language server which is very slow and you want diagnostics to
show up even when you're actively typing (diagnostics received for old document versions are discarded)."))

  (group CodeActionSettings "text.code-actions"
    (setting sign "string" "⚑"
      "Character to use as sign for lines where code actions are available. Empty string or null means no sign will be shown for
code actions.")

    (setting sign-width "int" 1
      "How many columns the sign occupies.")

    (setting sign-color "string" "info"
      "What color the sign for code actions should be. Can be a theme color name or hex code (e.g. `#12AB34`)."))

  (group ColorHighlightSettings "text.color-highlight"
    (setting enable "bool" false
      "Add colored inlay hints before any occurance of a string representing a color. Color detection is configured per language
in `text.color-highlight.{language-id}.`")

    (setting regex "RegexSetting" "#([0-9a-fA-F]{6})|#([0-9a-fA-F]{8})"
      "Regex used to find colors. Use capture groups to match one or more numbers within a color definition, depending on the kind.")

    (setting kind "ColorType" hex
      "How to interpret the number.
'hex' means the number is written as either 6 or 8 hex characters, e.g. ABBACA7.
'float1' means the number is a float with 0 being black and 1 being white.
'float255' means the number is a float or int with 0 being black and 255 being white."))

  (group TextSettings "text"
    (setting tab-width "int" 4
      "How many characters wide a tab is.")

    (setting line-comment "Option[string]" nil
      "String which starts a line comment")

    (setting indent-after "Option[seq[string]]" nil
      "When you insert a new line, if the current line ends with one of these strings then the new line will be indented.")

    (setting completion-word-chars "RuneSetSetting" [["a" "z"] ["A" "Z"] ["0" "9"] "_"]
      "")

    (setting indent "IndentStyleKind" spaces
      "Whether to used spaces or tabs for indentation. When indent detection is enabled then this only specfies the default
for new files and files where the indentation type can't be detected automatically.")

    (setting auto-reload "bool" false
      "If true then files will be automatically reloaded when the content on disk changes (except if you have unsaved changes).")

    (setting add-new-file-vcs "bool" false
      "If true then newly saved files will be added to the vcs (only for perforce right now, does nothing for git)")

    (setting add-new-file-vcs-prompt "bool" true
      "If true then you will be prompted when saving a new file on whether to add it to the vcs, otherwise the file is always added.")

    (setting inclusive-selection "bool" false
      "Specifies whether a selection includes the character after the end cursor.
If true then a selection like (0:0...0:4) with the text 'Hello world' would select 'Hello'.
If false then the selected text would be 'Hell'.
If you use Vim motions then the Vim plugin manages this setting.")

    (setting cursor-margin-relative "bool" true
      "Whether `text.cursor-margin` is relative to the screen height (0-1) or an absolute number of lines.")

    (setting cursor-margin "float" 0.15
      "How far from the edge to keep the cursor, either percentage of screen height (0-1) or number of lines,
depending on `text.cursor-margin-relative`.")

    (setting wrap-lines "bool" true
      "Enable line wrapping.")

    (setting wrap-margin "int" 1
      "How many characters from the right edge to start wrapping text.")

    (setting default-mode "string" ""
      "Default mode to set when opening/creating text documents.")

    (setting search-workspace-regex-max-results "int" 50000
      "Maximum number of results to display for regex based workspace symbol search.")

    (setting choose-cursor-max "int" 300
      "Maximum number of locations to highlight choose cursor mode.")

    (setting control-click-command "string" "goto-definition"
      "Command to run after control clicking on some text.")

    (setting control-click-command-args "JsonNode" []
      "Arguments to the command which is run when control clicking on some text.")

    (setting single-click-command "string" ""
      "Command to run after single clicking on some text.")

    (setting single-click-command-args "JsonNode" []
      "Arguments to the command which is run when single clicking on some text.")

    (setting double-click-command "string" "extend-select-move"
      "Command to run after double clicking on some text.")

    (setting double-click-command-args "JsonNode" ["word" true]
      "Arguments to the command which is run when double clicking on some text.")

    (setting triple-click-command "string" "extend-select-move"
      "Command to run after triple clicking on some text.")

    (setting triple-click-command-args "JsonNode" ["line" true]
      "Arguments to the command which is run when triple clicking on some text.")

    (setting scroll-to-change-on-reload "Option[bool]" false
      "If not null then scroll to the changed region when a file is reloaded.")

    (setting scroll-to-end-on-insert "bool" false
      "If true then scroll to the end of the file when text is inserted at the end and the cursor
is already at the end.")

    (setting modes "seq[string]" ["editor.text"]
      "List of input modes text editors.")

    (setting completion-mode "string" "editor.text"
      "Mode to activate while completion window is open.")

    (setting hover-mode "string" "editor.text.hover"
      "Mode to activate while hover window is open.")

    (setting tab-stop-mode "string" "editor.text.tab-stop"
      "Mode to activate while hover window is open.")

    (setting mode-changed-handler-command "string" ""
      "Command to execute when the mode of the text editor changes")

    (setting signature-help-enabled "bool" true
      "Whether signature help is enabled.")

    (setting signature-help-delay "int" 200
      "How often (in milliseconds) to update signature help while typing.")

    (setting signature-help-move "string" "(ts \\'call.inner\\') (overlapping) (last)"
      "Which move to use to find the beginning of the argument list when showing signature help.")

    (setting signature-help-trigger-chars "seq[string]" ["("]
      "Which characters trigger signature help when inserted.")

    (setting signature-help-trigger-on-edit-in-args "bool" true
      "Trigger signature help when editing inside an argument list, as defined by 'signature-help-move'")

    (setting auto-insert-close "bool" true
      "Automatically insert closing parenthesis, braces, brackets and quotes.")

    (setting disable-completions "bool" false
      "Disable auto completion")

    (setting disable-scrolling "bool" false
      "Disable scrolling"))

  (group UnsavedSettings "unsaved"
    (setting interval "int" 60
      "How often (in seconds) the editor auto saves unsaved files. Set to 0 to disable auto saving.")

    (setting behaviour "UnsavedBehaviour" none
      "What to do with unsaved files.
`none` - Don't save unsaved files automatically. Files are only saved through the explicit `save` command
`temp` - Save unsaved files to temp files in `app://unsaved` (for non-existing files) or `ws0://.nev/unsaved` for existing files.
`real` - Save existing files to the actual real file. Non-existing files are still saved to `app://unsaved`"))

  (group DebugSettings "debug"
    (setting log-text-render-time "bool" false
      "Log how long it takes to generate the render commands for a text editor.")

    (setting draw-text-chunks "bool" false
      "GUI only: Highlight text chunks")

    (setting log-to-internal-document "bool" false
      "Write logs to an internal document which can be opened using the `logs` command."))

  (group LspMergeSettings "lsp-merge"
    (setting timeout "int" 10000
      "Timeout for LSP requests in milliseconds"))

  (group PluginSettings "plugins"
    (setting watch-plugin-directories "bool" true
      "Whether to watch the plugin directories for changes and load new plugins")

    (setting command-load-behaviour "PluginCommandLoadBehaviour" async-or-wait
      "Defines if and how to run commands which trigger a plugin to load.
'dont-run': Don't run the command after the plugin is loaded. You have to manually run the command again.
'async-run': Asynchronously load the plugin and run the command afterwards. If the command returns something
             then the return value will not be available if the command is e.g. called from a plugin.
'wait-and-run': Synchronously load the plugin and run the command afterwards. Return values work fine, but the editor
                will freeze while loading the plugin.
'async-or-wait': Use 'async-run' behaviour for commands with no return value and 'wait-and-run' for commands with return values." ))

  (group SelectorSettings "selector"
    (setting base-mode "string" "popup.selector"
      "")

    (setting min-score "float" 0
      ""))

  (group TerminalSettings "terminal"
    (setting default-mode "string" ""
      "Input mode to activate when creating a new terminal, if no mode is specified otherwise.")

    (setting base-mode "string" "terminal"
      "Input mode which is always active while a terminal view is active.")

    (setting idle-threshold "int" 500
      "After how many milliseconds of no data received from a terminal it is considered idle, and can be reused
for running more commands."))

  (group ContextLineSettings "context-lines"
    (setting enabled "bool" true
      "")

    (setting style "string" "breadcrumb"
      "")

    (setting separator "string" "»"
      "")

    (setting show "RegexSetting" "(definition\.(.*))"
      "")

    (setting show-conditionals "bool" true
      "")

    (setting show-classes "bool" true
      "")

    (setting show-functions "bool" true
      "")

    (setting show-modules "bool" true
      ""))

  (group FormatSettings "formatter"
    (setting on-save "bool" false
      "If true run the formatter when saving.")

    (setting type "string" ""
      "What type of formatter to use. Leave empty for the default formatter which uses 'formatter.command'")

    (setting command "seq[string]" []
      "Command to run. First entry is path to the formatter program, subsequent entries are passed as arguments to the formatter.
")

    (setting input "FormatterInput" temp-file
      "How input is passed to the formatter
`temp-file`: When formatting the file is saved to a temporary file and the formatter is run on the temporary file
`file`: The formatter is run on the actual file. Make sure to save first.
`stdin`: The file is passed to the formatter through stdin, and the formatter is expected to write the formatted output to stdout
."))

)
