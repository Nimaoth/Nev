# Nev documentation

This file contains documentation about features that don't fit into any of the other docs.
- [Build from source](docs/building_from_source.md)
- [Getting started](docs/getting_started.md)
- [Cheatsheet](docs/cheatsheet.md)
- [Configuration](docs/configuration.md)
- [Finders](docs/finders.md)
- [Plugin API](https://nimaoth.github.io/AbsytreeDocs/scripting_nim/htmldocs/theindex.html).
- [Virtual filesystem](docs/virtual_file_system.md)

## Command aliases

To create an alias for a command add this to a config file:

```json
// settings.json
{
  "alias.q": "quit",
  "alias.wq": ["write-file", "quit"],

  // alternative syntax (use + to add new aliases without deleting existing ones defined in prior configs):
  "+alias": {
    "q": "quit",
    "wq": ["write-file", "quit"],
  }
}
```

This defines two aliases `w` and `wq`. When you run the `w` command it will run `quit`,
and if you run `wq` then it will run `write-file` and then `quit`.

Aliases can use other aliases, so the following is possible:

```json
// settings.json
{
  "alias.q": "quit",
  "alias.wq": ["write-file", "q"],
}
```

Aliases can be bound to keys, so the following will run the `wq` alias when pressing `<SPACE>wq`:

```json
// keybindings.json
{
    "editor": {
        "<SPACE>wq": "wq",
    },
}
```

You can specify parameters and forward parameters in aliases:

```json
// settings.json
{
  "alias.q": "quit-immediately 1",
  "alias.wq": ["write-file @0", "quit-immediately @1"],
  "alias.echo": [
    // the echo-args command just logs all arguments to the log file
    "echo-args @0 @1",
    "echo-args @",
    "echo-args @@"
  ],
}
```

`@@` refers to all arguments, `@n` refers to the nth argument and `@` refers to the remaining arguments after the previous `@n` (or all arguments if there is no `@n` before)

The remaining arguments for `@` are tracked across multiple commands, so in this example the second `echo-args` command
doesn't receive any arguments if you only pass two arguments to the alias, because the first command already consumes both.

You can use the same indices for `@n` multiple times.

Here are some examples of running these aliases and the commands that will be executed:
- `q` -> `quit-immediately 1`
- `wq "test.txt" 1` -> `write-file "test.txt"`, `quit-immediately 1`
- `echo "a" "b"` -> `echo-args "a" "b"`, `echo-args`, `echo-args "a" "b"`
- `echo "a" "b" "c" "d"` -> `echo-args "a" "b"`, `echo-args "c" "d"`, `echo-args "a" "b" "c" "d"`

## Terminal

Nev has a builtin terminal. To create a terminal view there are two commands:
- `create-terminal <command> [<options>]` - Creates a new terminal view, running the specified command. Usually the command is something like `bash` or `powershell`:
```nim
  ## Opens a new terminal by running `command`.
  ## `command`                   Program name and arguments for the process. Usually a shell.
  ## `options.group`             An arbitrary string used to control reusing of terminals and is displayed on screen.
  ##                             Can be used to for example have a `scratch` group and a `build` group.
  ##                             The `build` group would be used for running build commands, the `scratch` group for
  ##                             random other tasks.
  ## `options.autoRunCommand`    Command to execute in the shell. This is passed to `command` through stdin,
  ##                             as if typed with the keyboard.
  ## `options.closeOnTerminate`  Close the terminal view automatically as soon as the connected process terminates.
  ## `options.mode`              Mode to set for the terminal view. Usually something like  "normal", "insert" or "".
```

- `run-in-terminal <shell> <command> [<options>]` - Runs a command in a terminal, assuming the terminal is running some shell like program.
```nim
## Run the given `command` in a terminal with the specified shell.
## `command` is executed in the shell by sending it as if typed using the keyboard, followed by `<ENTER>`.
## `shell`                     Name of the shell. If you pass e.g. `wsl` to this function then the shell which gets
##                             executed is configured in `editor.shells.wsl.command`.
## `options.reuseExisting`     Run the command in an existing terminal if one exists. If not a new one is created.
##                             An existing terminal is only used when it has a matching `group` and `shell`, and
##                             it is not busy running another command (detecting this is sometimes wrong).
## `options.group`             An arbitrary string used to control reusing of terminals and is displayed on screen.
##                             Can be used to for example have a `scratch` group and a `build` group.
##                             The `build` group would be used for running build commands, the `scratch` group for
##                             random other tasks.
## `options.closeOnTerminate`  Close the terminal view automatically as soon as the connected process terminates.
## `options.mode`              Mode to set for the terminal view. Usually something like  "normal", "insert" or "".o
```

### Controls

The terminal by default has two modes, "normal" and "insert".
In insert mode almost every key press is forwarded to the terminal by default.
You can still override keys in insert mode (and by default `F9` is mapped to exit to normal mode).

In normal mode only some keys are send to the terminal by default (e.g. arrow keys, home/end, enter, i/I/a/A to enter insert mode, etc.)

- `insert` mode:
  | Key | Description | Mode |
  | ----------- | --- | --- |
  | `<F9>`/`cf` | Exit to normal mode. `cf` has to be pressed quickly. |
  | `<C-ENTER>` | Enter and exit to normal mode. |

- `normal` mode:
  | Key | Description | Mode |
  | ----------- | --- | --- |
  | `i`/`I`/`a`/`A` | Switch to insert mode. Behavior matches Vim. |
  | `<ENTER>`, `<HOME>`, `<END>`, arrow keys | Send to the shell like in insert mode
  | `CS-UP` | Scroll up |
  | `CS-DOWN` | Scroll down |
  | `<C-u>`/`CS-PAGE_UP` | Scroll up more |
  | `<C-d>`/`CS-PAGE_DOWN` | Scroll down more |
  | `gg`/`CS-HOME` | Scroll to the top. |
  | `G`/`CS-END` | Scroll to the bottom. |
  | `<C-v>`/`p` | Paste from clipboard |
  | `C-e` | Open the terminal output in a text editor, allowing you to e.g. search through it |

### Open hidden terminals

To open a hidden terminal you can't use the `choose-open` command, as that command only shows files you have open.
You need to use the `select-terminal` command instead (`<SPACE>to` by default, `to` standing for "terminal open").

The `select-terminal` command show all hidden terminals, and allows you to use the terminal directly from within
the popup by focusing the preview using `<TAB>`.

To open the terminal in the main view just press `<ENTER>` or `<C-y>`.

### Examples

#### Open a scratch terminal using a key combination

```json
// keybindings.json
{
    "editor": {
        "<SPACE>ts": [
            "run-in-terminal",
            "bash",
            "", // Empty command, so the terminal is just opened and ready for you to enter something.
            {
                "mode": "insert",
                "closeOnTerminate": true,
                "group": "scratch",
            }
        ]
    }
}
```

With this configuration you can then do the following:
- Press `<SPACE>ts` for the first time to open a new terminal running bash, and starting out in insert mode.
- If you already have a scratch terminal open, pressing `<SPACE>ts` will show/focus that terminal if it is currently idle, or open a second scratch terminal otherwise.
- If you exit the shell, the terminal view will close immediately. Closing the view obviously terminates the shell session as well.

#### Run a build using a key combination
```json
// keybindings.json
{
    "editor": {
        "<SPACE>zb": [
            "all", // Runs all arguments as commands, allowing you to bind multiple commands in a single key combination.
            [
                "run-in-terminal",
                "bash",
                "clear; nimble build", // Clear the screen, the run `nimble build`
                {
                    "mode": "normal", // Set the terminal to normal mode
                    "closeOnTerminate": false,
                    "group": "build-run", // Group for reusing the terminal when building
                }
            ],
            ["next-view"] // After the `run-in-terminal` command the terminal view will be focused, used `next-view`
                          // to focus the original view again.
        ]
    }
}
```

#### Force open a new terminal running NeoVim
```json
// keybindings.json
{
    "editor": {
        "<SPACE>tn": [
            "create-terminal",
            "bash",
            {
              "autoRunCommand": "nvim ; exit" // Run NeoVim, then exit the shell.
            }
        ]
    }
}
```