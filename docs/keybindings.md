# Keybindings System Overview

You can map key combinations to **commands** that perform actions in the editor. These bindings are defined per **input mode** (like `vim.normal` or `vscode`) and set up mostly in various `keybindings.json` files.

## Key Concepts

* **Input modes** are named contexts that group keybindings.
* A **stack of active input modes** determines which keybindings are active
* **Higher modes in the stack take priority** over lower ones when resolving keybindings.
* Input modes are dynamically activated based on e.g. editor focus.

---

## Input Mode Stack Mechanics

At any given time, a combination of modes is active. Here's how mode resolution works:

* **Base Modes** are always active, regardless of focus.
* **Contextual Modes** (like `vim.insert` or `vim.completion`) are added depending on the state of the focused view.
* Keybinding resolution walks the stack **top to bottom**, using the first matching binding.

Example input mode stack when using Vim keybindings:

```
vim.completion       ← top (from `text.completion-mode`)    -|
vim.insert           ← added dynamically                     | These come from the active editor
vim                  ← from `text.modes`                    -|
vim.base             ← bottom (from `editor.base-modes`)    -  This one is always active
```

---

## Input mode settings

| Setting                                | Purpose                                                       |
| -------------------------------------- | ------------------------------------------------------------- |
| `editor.base-modes`                    | Always-active modes, regardless of focus                      |
| `text.modes`                           | Modes active when a **text editor** is focused. These are changed dynamically when using Vim keybindings |
| `text.default-mode`                    | Default mode added to `text.modes` for a text editor          |
| `text.completion-mode`                 | Mode added when the **completion window** is visible          |
| `editor.command-line-mode-low`         | Input mode added during **command-line mode** (low priority)  |
| `editor.command-line-mode-high`        | Input mode added during **command-line mode** (high priority) |
| `editor.command-line-result-mode-low`  | Mode active during **command-line result** (low)              |
| `editor.command-line-result-mode-high` | Mode active during **command-line result** (high)             |
| `terminal.base-mode`                   | Always-active mode when **terminal** is focused               |
| `terminal.default-mode`                | Optional additional terminal mode                             |
| `selector.base-mode`                   | Always-active mode when a **selector popup** is open          |

### Selector Popup Mode Composition

When a selector popup is open, the following rules apply:

* The base mode (e.g., `vim.selector`) is always added.
* A **scope-specific mode** is added:

  * For selector scope `themes` → `vim.selector.themes`
* If the preview is focused, the preview mode is added:

  * → `vim.selector.preview`

---

## Input Mode Stack Examples
These examples assume using Vim keybindings, with the modes defined like [this](../config/settings-vim.json)
| Context                                  | Active Input Modes (Bottom → Top)                                                                  |
| ----------------------------------------- | -------------------------------------------------------------------------------------------------- |
| Selector popup for themes (preview not focused)    | `vim.base`, `vim.selector`, `vim.selector.themes`                                                  |
| Selector popup for themes (preview focused)  | `vim.base`, `vim.selector`, `vim.selector.preview`                                                 |
| Text editor in **normal mode**    | `vim.base`, `vim`, `vim.normal`                                                                    |
| Text editor in **insert mode**            | `vim.base`, `vim`, `vim.insert`                                                                    |
| Text editor in **insert mode** and completions open   | `vim.base`, `vim`, `vim.insert`, `vim.completion`                                                  |
| Terminal in **normal mode**               | `vim.base`, `terminal`, `normal`                                                                   |
| Command-line in insert mode + completions | `vim.base`, `vim`, `vim.insert`, `vim.command-line-low`, `vim.completion`, `vim.command-line-high` |

---

## Switching Keybinding Sets

Use the `extra-settings` key to change which keybinding scheme to use (Vim is the default):

### Example

```json
// app://config/settings.json
{
    "extra-settings": ["app://config/settings-vim.json"]
}
```

This loads modes like `vim.base`, `vim`, `vim.normal`, etc.

To switch to a different scheme (e.g., VSCode-style), replace it with:

```json
"extra-settings": ["app://config/settings-vscode.json"]
```

---

# Creating Custom Keybindings

You can define your own keybindings and create new **input modes**.
Check out [the default keybindings](../config/keybindings.json) for a lot more examples

---

## Where to Place Keybindings

Create or edit the following file to add your own keybindings:

* **Linux**: `~/.nev/keybindings.json`
* **Windows**: `%HOME%/.nev/keybindings.json`

Each top-level key represents an **input mode**, and the object under it defines key-to-command mappings.

---

## Example: Add a Maximize View Shortcut

To bind `<LEADER>m` in Vim Normal mode and `<C-m>` in VSCode mode to maximize the current view:

```json
// ~/.nev/keybindings.json
{
    "vscode": {
        "<C-m>": ["toggle-maximize-view"]
    },
    "vim.normal": {
        "<LEADER>m": ["toggle-maximize-view"]
    }
}
```

### More examples

```json
{
    "vim.base": {
        "<C-w>h": ["focus-view-left"]
    },
    "vim": {
        ":": ["command-line"]
    },
    "vim.normal": {
        "a": ["vim-insert-mode", "right"],
        "i": ["vim-insert-mode"]
    },
    "vim.insert": {
        "<C-w>": ["vim-delete-word-back"],
        "<C-u>": ["vim-delete-line-back"]
    },
    "vim.selector": {
        // selector global keybindings
    },
    "vim.selector.themes": {
        // keybindings specific to theme selector
    },
    "vscode.base": {
        // VSCode-style base bindings
    },
    "vscode": {
        // VSCode-style editor bindings
    }
}
```

---

# Creating a Custom Input Mode

This example shows how to create a custom vim mode ( `vim.my-mode`).

---

## Step 1: Configure Mode Behavior

Add the following to `~/.nev/settings.json` to define how your custom mode should behave:

```json
{
    // Whether to allow character input to be inserted when not bound to commands
    "input.vim.my-mode.handle-inputs": true, // default: false

    // Whether to allow keybindings to trigger commands in this mode
    "input.vim.my-mode.handle-actions": true, // default: true

    // If true, prevents any commands from lower-priority modes from being executed
    "input.vim.my-mode.consume-all-actions": false, // default: false

    // If true, prevents any text input from being handled by lower modes
    "input.vim.my-mode.consume-all-input": false, // default: false

    // Controls how the cursor moves for certain commands
    // "last" moves only the selection end, "first" moves the start, "both" moves both
    "editor.text.cursor.movement.vim.my-mode": "last",

    // Makes the cursor appear as a block (true) or a line (false)
    "editor.text.cursor.wide.vim.my-mode": true
}
```

---

## Step 2: Add Keybindings for the Custom Mode

Extend your `keybindings.json` to define the behavior of your new mode:

```json
// ~/.nev/keybindings.json
{
    "vim.my-mode": {
        "<ESCAPE>": ["set-mode", "vim.normal"],  // Exit to normal mode
        "x": ["undo"]                             // Example: bind 'x' to undo
    },
    "vim.normal": {
        "<C-i>": ["set-mode", "vim.my-mode"]     // Enter your custom mode
    }
}
```

---

## Mode Switching for Text Editors: `set-mode` and `remove-mode`

### `set-mode`

The command `set-mode` adds a new mode to the active **text editor** and **removes other modes with the same prefix**.

For example:

* `set-mode vim.normal` → removes `vim.insert`, adds `vim.normal`
* `set-mode other.mode` → does **not** affect `vim.*` modes

### `remove-mode`

If you want to manually remove a mode without replacing it:

```json
["remove-mode", "other.mode"]
```

---

### Special Keys

Use angle brackets for special keys:

* `<ENTER>`, `<ESCAPE>`, `<SPACE>`, `<BACKSPACE>`, `<TAB>`, `<DELETE>`
* Arrow keys: `<LEFT>`, `<RIGHT>`, `<UP>`, `<DOWN>`
* Others: `<HOME>`, `<END>`, `<PAGE_UP>`, `<PAGE_DOWN>`
* Function keys: `<F1>` to `<F12>`

### Modifiers

Modifiers use the following abbreviations:

* `C` = Control
* `S` = Shift
* `A` = Alt

Example:

```json
"<C-HOME>": ["command"]            // CTRL+HOME
"<CS-a>": ["command"]           // CTRL+SHIFT+a
```

Note: Uppercase letters (e.g. `"A"`) are treated as `SHIFT+a`.

---

## Multi-Key Sequences

Keybindings can be **multi-key sequences**, like `"d<text_object>"` or `"<SPACE><C-g>"`. The editor uses a state machine for each mode that processes each key in sequence.

⚠️ Don't bind keys that are prefixes of other bindings in the same mode:

```json
"a": ["command-a"],
"aa": ["command-aa"] // This will never be triggered because "a" triggers first
```

---

## Insert Mode Input Delay

In insert mode or other input-consuming modes, bindings like `"jj"` can coexist with normal typing:

```json
"vim.insert": {
  "jj": ["set-mode", "vim.normal"]
}
```

Behavior depends on timing:

* `j` → delay passed → inserts `j`
* `jj` → quick press → exits to normal mode
* `jk` → `j` inserted, `k` handled normally

Configure the delay with:

```json
"editor.insert-input-delay": 300 // milliseconds
```

---

## Repeatable Keybindings (`*` Modifier)

Use `*` to allow repeating the last part of a keybinding:

```json
"vim.normal": {
  "<C-w><*-f>-": ["change-font-size", -1],
  "<C-w><*-f>+": ["change-font-size", 1]
}
```

After pressing `<C-w>f`, you can press `+` or `-` repeatedly without restarting the sequence.

---

## Submodes and Composability

Submodes are used to compose complex keybindings using reusable parts (like Vim-style motions and text objects).

### Defining Submodes

```json
{
  "#count": {
    "<-1-9><o-0-9>": [""]
  },

  "vim#text_object": {
    "<?-count>iw": ["vim-select-text-object", "vim-word-inner", false, true, "<#text_object.count>"],
    "<?-count>i{": ["vim-select-surrounding", "vim-surround-{-inner", false, true, "<#text_object.count>"]
  }
}
```

* `#` in the mode name indicates a sub mode
* sub modes can be used in main modes with suffixes, e.g the `text_object` submode can be used in any mode starting with `vim`,
  the `count` submode can be used in any mode.
* `<?-count>` = optional count prefix
* `<#text_object.count>` = pass captured count as numeric argument

### Using Submodes in a Main Mode

```json
"vim.normal": {
  "<?-count>d<text_object>": ["vim-delete-move <text_object> <#count>"],
  "<?-count>c<text_object>": ["vim-change-move <text_object> <#count>"]
}
```

This results in bindings like:

* `3d2iw` → `vim-delete-move "vim-select-text-object \"vim-word-inner\" false true 2" 3`

---

## How It Works Internally

* Each input mode is compiled into a **state machine**
* Each keybinding is a sequence of states (one per key), the end state contains the bound command
* Each key press advances the current state of each input modes state machine, going from top to bottom through the stack
* Reaching an **end state** executes the command and aborts all other input mode state machines in the input mode stack
* Submodes are inserted into the state machine of the main mode
* Repeatable sequences (`<*>`) change the default mode after a keybinding finishes to the tagged state instead of the start state.
