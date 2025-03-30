
# Incompleted list of all settings

For examples and default values see [here](../config/settings.json)

| Key | Type | Default | Description |
| ----------- | --- | --- | ------ |
| `editor.text.auto-start-language-server` | bool | true | If true then documents automatically start and connect to a language server if one is configured for the language. |
| `editor.text.triple-click-command` | string | "extend-select-move" | Command to execute when triple clicking |
| `editor.text.triple-click-command-args` | array | ["line", true] | Arguments to pass to the command when triple clicking |
| `editor.text.whitespace.char` | char | "·" | The character to use to rendering spaces |
| `editor.text.whitespace.color` | string | "comment" | Hex color or color name to use for rendering spaces. |
| `editor.text.cursor.context-lines` | bool | true | If true then the editor uses treesitter to show the first line of parent nodes at the top. |
| `editor.text.line-numbers` | "none" "absolute" "relative" | "absolute" | How line numbers are displayed. |
| `editor.restore-open-workspaces` | bool | true | If true then the editor will load workspaces from the session (if a session is opened). |
| `editor.restore-open-editors` | bool | true | If true then the editor will restore open editors from the session (if a session is opened). |
| `editor.close-unused-documents-timer` | number (seconds) | 10 | How often the editor checks if any currently open documents are unused and closes them. |
| `editor.max-views` | number | 2 | Maximum number of views (files or other UIs) which can be shown. |
| `editor.record-input-history` | bool | false | Whether the editor shows a history of the last few pressed buttons in the status bar |
| `editor.clear-input-history-delay` | number (ms) | 3000 | After how many milliseconds of no input the input history is cleared. |
| `editor.lsp` | object | --- | Language server configuration per langugae. [More info](lsp.md) |
| `language-mappings` | object | --- | Mapping of regex to language id, used to assign langugae ids by file extension/path. |
| `languages` | object | --- | Mapping of language id to language config, used to specify various settings per language. See [here](../config/settings.json) |
| `text.reload-diff` | bool | true | If true, when reloading a text document from disk, the editor will calculate the diff between the version on disk and in memory, and apply that diff, instead of overriding the entire file content in memory. This can save memory in the long run, but increases memory usage while loading and potentially increases loading time. |
| `text.reload-diff-timeout` | number (ms) | 250 | When `text.reload-diff` is true, the diff process is canceled after this time and the file is reloaded normally. |
| `snippets` | object | --- | Snippets per language. |
| `wasm-plugin-post-load-commands` | array | --- | List of commands to execute after loading wasm plugins. |
| `wasm-plugin-post-reload-commands` | array | --- | List of commands to execute after reloading wasm plugins. |
| `keybindings.preset` | "vim" "vscode" | "vim" | Which kind of keybindings to load at startup. |
| `ui.background.transparent` | bool | false | If true then the background is not filled (don't use in GUI version) |
| `ui.theme` | bool | "app://themes/tokyo-night-color-theme.json" | Path to the theme. |
| `ui.smooth-scroll` | bool | true | If true then scrolling is smooth. |
| `ui.cursor-trail` | number (int) | 2 | How long of a trail to render when the cursor moves. |
| `ui.which-key-delay` | number (ms) | 250 | After how many seconds the editor will show a window with possible next inputs after pressing a key which doesn't immediately execute an action. |
| `ui.which-key-height` | number | 6 | How many rows tall the window showing next possible inputs should be. |
| `ui.which-key-no-progress` | bool | false | If true then the window showing next possible inputs will be displayed even when no keybinding is in progress (i.e. it will always be shown). |
| `ui.selector-popup.which-key-height` | int | 5 | How many rows tall the window showing next possible inputs is in popups. |
| `ui.smooth-scroll-speed` | bool | 15.0 | todo |
| `ui.highlight` | bool | true | Enable/disable syntax highlighting globally. |
| `ui.indent-guide` | bool | true | If true then an indent guide is rendered to show the indentation of the current line. |
| `ui.cursor-speed` | number | 100.0 | How fast the cursor trail moves. Higher is faster. |
| `ui.selector.show-score` | bool | false | Show the fuzzy matching score for each row in a selector popup. |

## For debugging
| Key | Type | Default | Description |
| ----------- | --- | --- | ------ |
| `editor.text.draw-chunks` | bool | false | Draw outline for every text chunk. Only test in GUI version. |
| `text.reload-diff-check` | bool | false | If true and `text.reload-diff` is true, the diff is checked for correctness. |
| `ui.log-text-render-time` | bool | false | If true log how long text rendering takes. |

## todo
| Key | Type | Default | Description |
| ----------- | --- | --- | ------ |
| `editor.text.highlight-treesitter-errors` | bool | false | todo |
| `editor.text.default-mode` | bool | false | todo |
| `editor.text.inclusive-selection` | bool | false | todo |
| `editor.text.cursor.wide.` | bool | false | todo |
| `editor.text.cursor.wide.normal` | bool | false | todo |
| `editor.text.cursor.movement.` | bool | false | todo |
| `editor.text.cursor.movement.normal` | bool | false | todo |
| `editor.text.languages-server` | bool | false | todo |
| `editor.custom-mode-on-top` | bool | false | todo |
| `platform.terminal-sleep-threshold` | number (ms) | 5 | todo |
| `ui.scroll-snap-min-distance` | bool | 0.5 | todo |
