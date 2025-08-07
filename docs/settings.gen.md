# List of (most) settings

For examples and default values see [here](../config/settings.json)

| Key | Type | Default | Description |
| ----------- | --- | --- | ------ |
| `debug.draw-text-chunks` | bool | false | GUI only: Highlight text chunks |
| `debug.log-text-render-time` | bool | false | Log how long it takes to generate the render commands for a text editor. |
| `debug.log-to-internal-document` | bool | false | Write logs to an internal document which can be opened using the `logs` command. |
| `editor.base-modes` | string[] | ["editor"] | List of input modes which are always active (at the lowest priority). |
| `editor.clear-input-history-delay` | int | 3000 | After how many milliseconds of no input the input history is cleared. |
| `editor.close-unused-documents-timer` | int | 10 | How often the editor will check for unused documents and close them, in seconds. |
| `editor.command-line-mode-high` | string | "command-line-high" | Global mode to apply while the command line is open. |
| `editor.command-line-mode-low` | string | "command-line-low" | Global mode to apply while the command line is open. |
| `editor.command-line-result-mode-high` | string | "command-line-result-high" | Global mode to apply while the command line is open showing a command result. |
| `editor.command-line-result-mode-low` | string | "command-line-result-low" | Global mode to apply while the command line is open showing a command result. |
| `editor.custom-mode-on-top` | bool | true | If true then the app mode event handler (if the app mode is not "") will be on top of the event handler stack, otherwise it will be at the bottom (but still above the "editor" event handler. |
| `editor.insert-input-delay` | int | 150 | After how many milliseconds of no input a pending input gets inserted as text, if you bind a key which inserts text in e.g. a multi key keybinding aswell. Say you bind `jj` to exit insert mode, then if you press `j` once and wait for this delay then it will insert `j` into the document, but if you press `j` again it will will exit insert mode instead. If you press another key like `k` before the time ends it will immediately insert the `j` and the `k`. |
| `editor.keep-session-history` | bool | true | If true then the editor will keep a history of opened sessions in home://.nev/sessions.json, which enables features like opening a recent session or opening the last session. |
| `editor.max-search-result-display-len` | int | 1000 | Max length of each individual search result (search results are cut off after this value). |
| `editor.max-search-results` | int | 1000 | Max number of search results returned by global text based search. |
| `editor.open-session.args` | JsonNodeEx[] \| null | null | Command arguments to use when opening a session in a new window. |
| `editor.open-session.command` | string \| null | null | Command to use when opening a session in a new window. |
| `editor.open-session.use-multiplexer` | bool | true | If true then Nev will detect if it's running inside a multiplexer like tmux, zellij or wezterm (by using environment variables) and if so opening a session will use the command `editor.open-session.tmux` or `editor.open-session.zellij` or `editor.open-session.wezterm` |
| `editor.print-statistics-on-shutdown` | bool | false | If true the editor prints memory usage statistics when quitting. |
| `editor.prompt-before-quit` | bool | false | If true then you will be prompted to confirm quitting even when no unsaved changes exist. |
| `editor.record-input-history` | bool | false | Whether the editor shows a history of the last few pressed buttons in the status bar. |
| `editor.save-in-session` | bool | true | Any editor with this set to true will be stored in the session and restored on startup. |
| `editor.watch-app-config` | bool | true | Watch the config files in the app directory and automatically reload them when they change. |
| `editor.watch-theme` | bool | true | Watch the theme directory for changes to the theme. |
| `editor.watch-user-config` | bool | true | Watch the config files in the user directory and automatically reload them when they change. |
| `editor.watch-workspace-config` | bool | true | Watch the config files in the workspace directory and automatically reload them when they change. |
| `lsp-merge.timeout` | int | 10000 | Timeout for LSP requests in milliseconds |
| `plugins.command-load-behaviour` | PluginCommandLoadBehaviour | "async-or-wait" | Defines if and how to run commands which trigger a plugin to load. "dont-run": Don't run the command after the plugin is loaded. You have to manually run the command again. "async-run": Asynchronously load the plugin and run the command afterwards. If the command returns something              then the return value will not be available if the command is e.g. called from a plugin. "wait-and-run": Synchronously load the plugin and run the command afterwards. Return values work fine, but the editor                 will freeze while loading the plugin. "async-or-wait": Use "async-run" behaviour for commands with no return value and "wait-and-run" for commands with return values. |
| `plugins.watch-plugin-directories` | bool | true | Whether to watch the plugin directories for changes and load new plugins |
| `selector.base-mode` | string | "popup.selector" |  |
| `terminal.base-mode` | string | "terminal" | Input mode which is always active while a terminal view is active. |
| `terminal.default-mode` | string | "" | Input mode to activate when creating a new terminal, if no mode is specified otherwise. |
| `terminal.idle-threshold` | int | 500 | After how many milliseconds of no data received from a terminal it is considered idle, and can be reused for running more commands. |
| `text.auto-reload` | bool | false | If true then files will be automatically reloaded when the content on disk changes (except if you have unsaved changes). |
| `text.choose-cursor-max` | int | 300 | Maximum number of locations to highlight choose cursor mode. |
| `text.code-actions.sign` | string | "⚑" | Character to use as sign for lines where code actions are available. Empty string or null means no sign will be shown for code actions. |
| `text.code-actions.sign-color` | string | "info" | What color the sign for code actions should be. Can be a theme color name or hex code (e.g. `#12AB34`). |
| `text.code-actions.sign-width` | int | 1 | How many columns the sign occupies. |
| `text.color-highlight.enable` | bool | false | Add colored inlay hints before any occurance of a string representing a color. Color detection is configured per language in `text.color-highlight.{language-id}.` |
| `text.color-highlight.kind` | "hex" \| "float1" \| "float255" | "hex" | How to interpret the number. "hex" means the number is written as either 6 or 8 hex characters, e.g. ABBACA7. "float1" means the number is a float with 0 being black and 1 being white. "float255" means the number is a float or int with 0 being black and 255 being white. |
| `text.color-highlight.regex` | regex | "#([0-9a-fA-F]{6})\|#([0-9a-fA-F]{8})" | Regex used to find colors. Use capture groups to match one or more numbers within a color definition, depending on the kind. |
| `text.completion-mode` | string | "editor.text.completion" | Mode to activate while completion window is open. |
| `text.completion-word-chars` | (string \| string[])[] | [["a","z"],["A","Z"],["0","9"],"_"] |  |
| `text.context-lines` | bool | true | Show lines containing parent nodes (like function, type, if/for etc) at the top of the window. |
| `text.control-click-command` | string | "goto-definition" | Command to run after control clicking on some text. |
| `text.control-click-command-args` | any | [] | Arguments to the command which is run when control clicking on some text. |
| `text.cursor-margin` | float | 0.15 | How far from the edge to keep the cursor, either percentage of screen height (0-1) or number of lines, depending on `text.cursor-margin-relative`. |
| `text.cursor-margin-relative` | bool | true | Whether `text.cursor-margin` is relative to the screen height (0-1) or an absolute number of lines. |
| `text.default-mode` | string | "" | Default mode to set when opening/creating text documents. |
| `text.diagnostics.enable` | bool | true | Enable diagnostics. Also requires a language server which supports diagnostics. |
| `text.diagnostics.snapshot-history` | int | 5 | How many snapshots to keep when editing. Snapshots are used to fix up diagnostic locations when receiving diagnostics for an older version of the document (e.g when you continue editing and the languages doesn't respond fast enough). You might want to increase this if you are using a language server which is very slow and you want diagnostics to show up even when you're actively typing (diagnostics received for old document versions are discarded). |
| `text.diff-reload.enable` | bool | true | When reloading a file the editor will compute the diff between the file on disk and the in memory document, and then apply the diff to the in memory version so it matches the content on disk. This can reduce memory usage when reloading files often (although it increases memory usage while reloading and increases load times). It's also better for collaboration as it doesn't affect the entire file. |
| `text.diff-reload.timeout` | int | 250 | Max number of milliseconds to use for diffing. If the timeout is exceeded then the file will be reloaded normally. |
| `text.double-click-command` | string | "extend-select-move" | Command to run after double clicking on some text. |
| `text.double-click-command-args` | any | ["word",true] | Arguments to the command which is run when double clicking on some text. |
| `text.formatter.command` | string[] | [] | Command to run. First entry is path to the formatter program, subsequent entries are passed as arguments to the formatter. |
| `text.formatter.on-save` | bool | false | If true run the formatter when saving. |
| `text.highlight-matches.delay` | int | 250 | How long after moving the cursor matching text is highlighted. |
| `text.highlight-matches.enable` | bool | true | Enable highlighting of text matching the current selection or word containing the cursor (if the selection is empty). |
| `text.highlight-matches.max-file-size` | int | 104857600 | Don't highlight matching text in files above this size (in bytes). |
| `text.highlight-matches.max-selection-length` | int | 1024 | Don't highlight matching text if the selection spans more bytes than this. |
| `text.highlight-matches.max-selection-lines` | int | 5 | Don't highlight matching text if the selection spans more lines than this. |
| `text.hover-delay` | int | 200 | How many milliseconds after hovering a word the lsp hover request is sent. |
| `text.inclusive-selection` | bool | false | Specifies whether a selection includes the character after the end cursor. If true then a selection like (0:0...0:4) with the text "Hello world" would select "Hello". If false then the selected text would be "Hell". If you use Vim motions then the Vim plugin manages this setting. |
| `text.indent` | "tabs" \| "spaces" | "spaces" | Whether to used spaces or tabs for indentation. When indent detection is enabled then this only specfies the default for new files and files where the indentation type can't be detected automatically. |
| `text.indent-after` | string[] \| null | null | When you insert a new line, if the current line ends with one of these strings then the new line will be indented. |
| `text.indent-detection.enable` | bool | true | Enable auto detecting the indent style when opening files. |
| `text.indent-detection.samples` | int | 50 | How many indent characters to process when detecting the indent style. Increase this if it fails for files which start with many unindented lines. |
| `text.indent-detection.timeout` | int | 20 | Max number of milliseconds to spend trying to detect the indent style. |
| `text.inlay-hints-enabled` | bool | true | Whether inlay hints are enabled. |
| `text.line-comment` | string \| null | null | String which starts a line comment |
| `text.mode-changed-handler-command` | string | "" | Command to execute when the mode of the text editor changes |
| `text.modes` | string[] | ["editor.text"] | List of input modes text editors. |
| `text.ripgrep.extra-args` | string[] | [] | Extra arguments passed to ripgrep |
| `text.ripgrep.file-type` | string \| null | null | Override the ripgrep type name. By default the documents language id is used. |
| `text.ripgrep.pass-type` | bool | true | Pass the --type argument to ripgrep using either the language id or the value from `file-type`. |
| `text.scroll-to-change-on-reload` | "first" \| "last" \| null | null | If not null then scroll to the changed region when a file is reloaded. |
| `text.scroll-to-end-on-insert` | bool | false | If true then scroll to the end of the file when text is inserted at the end and the cursor is already at the end. |
| `text.search-regexes.goto-declaration` | regex \| null | null | Regex to use when using the goto-declaration feature. |
| `text.search-regexes.goto-definition` | regex \| null | null | Regex to use when using the goto-definition feature. |
| `text.search-regexes.goto-implementation` | regex \| null | null | Regex to use when using the goto-implementation feature. |
| `text.search-regexes.goto-references` | regex \| null | null | Regex to use when using the goto-references feature. |
| `text.search-regexes.goto-type-definition` | regex \| null | null | Regex to use when using the goto-type-definition feature. |
| `text.search-regexes.show-only-matching-part` | bool | true | If true then the search results will only show the part of a line that matched the regex. If false then the entire line is shown. |
| `text.search-regexes.symbols` | regex \| null | null | Regex to use when using the symbols feature. |
| `text.search-regexes.workspace-symbols` | regex \| null | null | Regex to use when using the workspace-symbols feature. |
| `text.search-regexes.workspace-symbols-by-kind` | { [key: string]: regex } \| null | null | Regex to use when using the workspace-symbols feature. Keys are LSP symbol kinds, values are the corresponding regex. |
| `text.search-workspace-regex-max-results` | int | 50000 | Maximum number of results to display for regex based workspace symbol search. |
| `text.signs.max-width` | int \| null | 2 | If `show` is `auto` then this is the max width of the sign column, if `show` is `yes` then this is the exact width. |
| `text.signs.show` | "auto" \| "yes" \| "no" \| "number" | "number" | Defines how the sign column is displayed. - auto: Signs are next to line numbers, width is based on amount of signs in a line. - yes: Signs are next to line numbers and sign column is always visible. Width is defined in `max-width` - no: Don't show the sign column - number: Show signs instead of the line number, no extra sign column. |
| `text.single-click-command` | string | "" | Command to run after single clicking on some text. |
| `text.single-click-command-args` | any | [] | Arguments to the command which is run when single clicking on some text. |
| `text.tab-width` | int | 4 | How many characters wide a tab is. |
| `text.treesitter.enable` | bool | true | Enable parsing code into ASTs using treesitter. Also requires a treesitter parser for a specific language. |
| `text.treesitter.language` | string \| null | null | Override the language name used for choosing the treesitter parser. If not set then the documents language id is used. |
| `text.treesitter.path` | string \| null | null | Override the path to the treesitter parser (.dll/.so/.wasm). By default |
| `text.treesitter.queries` | string \| null | null | Path relative to the repository root where queries are located. If not set then the editor will look for the queries. |
| `text.treesitter.repository` | string \| null | null | Path relative to the repository root where queries are located. If not set then the editor will look for the queries. |
| `text.trim-trailing-whitespace.enabled` | bool | true | If true trailing whitespace is deleted when saving files. |
| `text.trim-trailing-whitespace.max-size` | int | 1000000 | Don't trim trailing whitespace when filesize is above this limit. |
| `text.triple-click-command` | string | "extend-select-move" | Command to run after triple clicking on some text. |
| `text.triple-click-command-args` | any | ["line",true] | Arguments to the command which is run when triple clicking on some text. |
| `text.wrap-lines` | bool | true | Enable line wrapping. |
| `text.wrap-margin` | int | 1 | How many characters from the right edge to start wrapping text. |
| `ui.background.inactive-brightness-change` | float | -0.025 | How much to change the brightness for inactive views. |
| `ui.background.transparent` | bool | false | If true the background is transparent. |
| `ui.cursor-trail-length` | int | 2 | How long the cursor trail is. Set to 0 to disable cursor trail. |
| `ui.cursor-trail-speed` | float | 100.0 | How fast to interpolate the cursor trail position when moving the cursor. Higher means faster. |
| `ui.font-family` | string | "app://fonts/DejaVuSansMono.ttf" | Full path to regular font file. |
| `ui.font-family-bold` | string | "app://fonts/DejaVuSansMono-Bold.ttf" | Full path to bold font file. |
| `ui.font-family-bold-italic` | string | "app://fonts/DejaVuSansMono-BoldOblique.ttf" | Full path to bold italic font file. |
| `ui.font-family-italic` | string | "app://fonts/DejaVuSansMono-Oblique.ttf" | Full path to italic font file. |
| `ui.hide-tab-bar-when-single` | bool | false | When true then tab layouts don't render a tab bar when they only have one tab. |
| `ui.indent-guide` | bool | true | Enable indent guides to show the indentation of the current line. |
| `ui.line-numbers` | "none" \| "absolute" \| "relative" | "absolute" | How line numbers should be displayed. |
| `ui.max-views` | int | 2 | Maximum number of views (files or other UIs) which can be shown. |
| `ui.scroll-speed` | float | 50.0 | How many pixels (or rows in the terminal) to scroll per scroll wheel tick. |
| `ui.smooth-scroll` | bool | true | Enable smooth scrolling. |
| `ui.smooth-scroll-snap-threshold` | float | 0.5 | Percentage of screen height at which the smooth scroll offset will be snapped to the target location. E.g. if this is 0.5, then if the smooth scroll offset if further from the target scroll offset than 50% of the screen height then the smooth scroll offset will instantly jump to the target scroll offset (-50% of the screen height). This means that the smooth scrolling will not take time proportional to the scroll distance for jumps bigger than the screen height. |
| `ui.smooth-scroll-speed` | float | 15.0 | How fast smooth scrolling interpolates. |
| `ui.syntax-highlighting` | bool | true | Enable syntax highlighting. |
| `ui.tab-header-width` | int | 30 | Width of tab layout headers in characters |
| `ui.theme` | string | "app://themes/tokyo-night-color-theme.json" | VFS path of the theme. |
| `ui.toast-duration` | int | 8000 | How long toasts are displayed for, in milliseconds. |
| `ui.which-key-delay` | int | 250 | After how many milliseconds the which key window opens. |
| `ui.which-key-height` | int | 6 | How many rows tall the window showing next possible inputs should be. |
| `ui.which-key-no-progress` | bool | false | If true then the window showing next possible inputs will be displayed even when no keybinding is in progress (i.e. it will always be shown). |
| `ui.whitespace-char` | string | "·" | Character to use when rendering whitespace. If this is the empty string or not set then spaces are not rendered. |
| `ui.whitespace-color` | string | "comment" | Color of rendered whitespace. Can be a theme key or hex color (e.g #ff00ff). |
