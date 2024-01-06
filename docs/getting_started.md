# Getting Started

For a list of all keybindings look at `default_config.nim` and `keybindings_normal.nim`/`keybindings_vim.nim`
To open this document at any time run the command `help`

By default the vim-like keybindings are enabled. They are inspired by vim but are not exactly the same.

The actual vim keybindings are not very complete yet (see [here](supported_vim_keybindings.md)), but those are supposed to be as close to vim as possible.

# Useful keybindings (C: Control, A: Alt, S: Shift)
- For `<LEADER>` you can either press `<SPACE>` or `<C-b>`
- `<ESCAPE>`: cancel or close e.g. popups
- `<C-x><C-x>`: quit
- `<LEADER><LEADER>`: enter the command line to run commands by name. (Aftwards press `<C-SPACE>` to see the list of builtin commands)
- `<LEADER>gf`: open the file chooser
- `<LEADER>ge`: open the file chooser (only shows files open in background)
- `<CA-x>`: close the current view
- `<CA-n>` and `<CA-t>`: switch between views
- `<C-s>`: save file

## Text Editor
- `<C-SPACE>`: show completion window
- with vim keybindings:
  - `gd`: go to definition
  - `gs`: go to symbol in current file

## Popups
- `<ENTER>` or `<TAB>`: select the currently selected item
- `<ESCAPE>`: close the popup
- `<UP>` or `<DOWN>`: select the next/previous item

# Useful commands
- `load-normal-keybindings`: load "normal" keybindings (like vs code)
- `load-vim-keybindings`: load vim keybindings (WIP). As close to vim as possible.
- `load-vim-like-keybindings`: load vim like keybindings (WIP). Inspired by vim, but with a lot of small differences.
- `logs`: show the log file

# Settings
There are a lot of settings which can be changed using `proc setOption*[T](path: string, value: T)` or `proc setOption*(option: string; value: JsonNode)`. Settings are stored in a JSON object, which also gets saved to the file `settings.json`. This file gets loaded before the config script, so the script can override any setting.

You can get the current value of a setting with `proc getOption*[T](path: string, default: T = T.default): T`

    setOption "editor.text.lsp.zig.path", "zls"
    echo getOption[string]("editor.text.lsp.zig.path") # zls

# Key bindings
You can bind different key combinations to __commands__. Each function exposed by the editor (see `absytree_api.nim`) has a corresponding command,
which has two names. If the function is called `myCommand`, then the command can be executed using either `myCommand` or `my-command`.

Key combinations are bound to a command and arguments for that command. The following binds the command `quit` to the key combination `CTRL-x + x`

    addCommand "editor", "<C-x>x", "quit"

Every key binding is specified using the config file, so just look at `absytree_config.nims` and `keybindings_*.nim` for reference.

Key combinations can be as long as you want, and contain any combination of modifiers, as long as the OS supports that combination.
Most keys can be specified using their ASCII value, i.e. to bind to e.g. the `k` key you would use `addCommand "editor", "k", "command-name"`.
Special keys like the space bar are specified using < and >: `addCommand "editor", "<SPACE>", "command-name"`.
The following special keys are defined:
- ENTER
- ESCAPE
- BACKSPACE
- SPACE
- DELETE
- TAB
- LEFT
- RIGHT
- UP
- DOWN
- HOME
- END
- PAGE_UP
- PAGE_DOWN
- F1, ..., F12

To specify that a modifier should be held down together with another key you need to used `<XXX-YYY>`, where `XXX` is any combination of modifiers
(`S` = shift, `C` = control, `A` = alt) and `YYY` is either a single ascii character for the key, or one of the special keys (e.g. `ENTER`).

If you use a upper case ascii character as key then this automatically means it uses shift, so `A` is equivalent to `<S-a>` and `<S-A>`

Some examples:

    addCommand "editor", "a", "command-name"
    addCommand "editor", "<C-a>", "command-name" # CTRL+a
    addCommand "editor", "<CS-a>", "command-name" # CTRL+SHIFT+a
    addCommand "editor", "<CS-SPACE>", "command-name" # CTRL+SHIFT+SPACE
    addCommand "editor", "SPACE<C-g>", "command-name" # SPACE, followed by CTRL+g

Be careful not to to this:

    addCommand "editor", "a", "command-name"
    addCommand "editor", "aa", "command-name" # Will never be used, because pressing a once will immediately execute the first binding

There is one special modifier `*` which means the following keys can be repeated without having to press the first keys again:

    # after pressing "<C-w>F", you can press "+" or "-" multiple times, and the input state machine resets to the <*-F> state instead of
    # to the beginning
    addCommand "editor", "<C-w><*-F>-", "change-font-size", -1
    addCommand "editor", "<C-w><*-F>+", "change-font-size", 1


All key bindings in the same scope (e.g. `editor`) will be compiled into a state machine. When you press a key, the state machine will advance,
and if it reaches and end state it will execute the command stored in the state (with the arguments also stored in the state).
Each `addCommand` corresponds to one end state.

# Scopes
The first parameter to `addCommand` is a scope. Different scopes can have different key bindings, even conflicting ones.
Depending on which scopes are active the corresponding commands will be executed.
Which scopes are active depends on which editor view is selected, whether there is e.g. a auto completion window open.
The scope stack looks like this
At the bottom of the scope stack is always `editor`.
- `editor`
- `editor.<MODE>`, if the editor mode is not `""` and `editor.custom-mode-on-top` is false. `<MODE>` is the current editor mode.
- One of the following:
  - `commandLine`, if the editor is in commandLine mode

  - If there is a popup open, then the following scopes:
    - If the popup is a goto popup, then the following scopes:
      - Same as a text editor (i.e. `editor.text`, etc)
    - If the popup is a selector popup, then the following scopes:
      - Same as a text editor (i.e. `editor.text`, etc)
      - `popup.selector`, always

  - If the selected view contains a text document, then the following scopes:
    - `editor.text`, always
    - `editor.text.<MODE>`, if the text editor mode is not `""`
    - `editor.text.completion`, if the text editor has a completion window open.

  - If the selected view contains a model document, then the following scopes:
    - `editor.model`, always
    - `editor.model.<MODE>`, if the model editor mode is not `""`

- `editor.<MODE>`, if the editor mode is not `""` and `editor.custom-mode-on-top` is true. `<MODE>` is the current editor mode.

So if you for example have text editor selected and a completion window is open, and the text editor is in `insert` mode, the scope stack would look like this:

- `editor` (bottom, handled by Editor)
- `editor.text` (handled by TextEditor)
- `editor.text.insert` (handled by TextEditor)
- `editor.text.completion` (top, handled by TextEditor)

If you have no completion window open and no mode selected then it would look like this:

- `editor` (bottom, handled by Editor)
- `editor.text` (top, handled by TextEditor)

When a key is pressed, the editor will advance the state machine for every scope in the stack, from top to bottom (i.e. the `editor` scope will always be last).
The first scope which reaches an end state will execute its' command, which will be handled by the owner of the scope. Then all state machines in the stack are reset.
The owners of the scopes are the following:
- `Editor`: `editor`, `commandLine`, `editor.<MODE>`
- `TextEditor`: `editor.text`, `editor.text.<MODE>`, `editor.text.completion`
- `ModelEditor`: `editor.model`, `editor.model.<MODE>`, `editor.model.completion`
- `SelectorPopup`: `popup.selector`

# Summary
To define keybindings specific for text documents (TextEditor), use:

    addCommand "editor.text", "a", "command-name"
    addTextCommand "", "a", "command-name"                  # Same as above

    addCommand "editor.text.insert", "a", "command-name"    # Insert mode
    addTextCommand "insert", "a", "command-name"            # Same as above

    addTextCommand "completion", "a", "command-name"        # Only active while completion window is open

    addTextCommandBlock "", "s":                            # First parameter is mode/"completion"
      ## Creates an anonymous action which runs this block. `editor` (automatically defined) is the text editor handling this command
      editor.setMode("insert")
      editor.selections = editor.delete(editor.selections)

    addTextCommand "", "a", proc(editor: TextDocumentEditor) =
      ## Creates an anonymous action which runs this lambda. `editor` is the text editor handling this command.
      # ...

    proc foo(editor: TextDocumentEditor) =
      # ...

    addTextCommand "", "a", foo                                 # Like above, but uses existing function

# Scripting API Documentation
The documentation for the scripting API is in scripting/htmldocs. You can see the current version [here](https://raw.githack.com/Nimaoth/AbsytreeDocs/main/scripting_nim/htmldocs/theindex.html) (using raw.githack.com) or [here](https://nimaoth.github.io/AbsytreeDocs/scripting_nim/htmldocs/theindex.html).

Here is an overview of the modules:
- `absytree_runtime`: Exports everything you need, so you can just include this in your script file.
- `scripting_api`: Part of the editor source, defines types used by both the editor and the script, as well as some utility functions for those types.
- `absytree_internal`: Ignore this. You shouldn't need to call these functions directly.
- `editor_api`: Contains general functions like changing font size, manipulating views, opening and closing files, etc.
- `editor_text_api`: Contains functions for interacting with a text editor (e.g. modifiying the content).
- `editor_model_api`: Contains functions for interacting with an model editor (e.g. modifying the content).
- `popupu_selector_api`: Contains functions for interacting with a selector popup.