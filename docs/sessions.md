# Sessions

Sessions allow you to keep your editor state, even if you close it. That way you don't need to reopen all the same files again, or add breakpoints all over again.

You can see which session is currently used in the bottom right of the editor.

If you don't have a session it will say `[No Session]`, otherwise it will show the name of the session:  `[Session: .nev-session]`

If you have a session file and want to modify it manually (e.g. to change workspace settings) then you should not edit the session file while you have that same session open, because once you exit the session file will be overridden.
Instead just edit it with `nev .nev-session`.

## Using sessions

If you launch the editor without a file as an argument then it will try to load a session from the default session file (`.nev-session`) in the current working directory.

To use a different session you can use `-s` like this: `nev -s:foo.nev-session`.

If you launch with a file path (like `nev foo.txt`) then it will only open that file, but not load a session.

## Opening sessions

- Nev keeps track of recently opened sessions in `~/.nev/sessions.json`
- You can open the last session you opened using `nev --restore-session` or `nev -e`
- You can open a session from your history using the `open-recent-session` command.
- You can open a session using the `open-session` command. This command takes a root directory and will
  search for `.nev-session` files in that directory and subdirectories and allow you to pick from the found sessions.

When opening a session, Nev will start a new process for the new session.
By default the command it runs to open the new session is `nev --session=...`.
`nev` in this case refers to the own executable, so if e.g. on windows you run the GUI version (`nevg`) it will run `nevg --session=...`.

On Windows this will mean it opens a new window if you run the GUI version.

Nev supports basic integration with terminal multiplexers like tmux, Zellij and Wezterm, meaning you can open a new session
in e.g. a new pane in tmux.

This is done using the commands specified in `editor.open-session.xzy`.
The default configuration looks like this:
```json
"editor.open-session.tmux": {
    "env": "TMUX",
    "command": "tmux",
    "args": ["split-window", ["exe"] , ["args"], "--terminal"],
},
"editor.open-session.zellij": {
    "env": "ZELLIJ",
    "command": "zellij",
    "args": ["run", "--", ["exe"] , ["args"], "--terminal"],
},
"editor.open-session.wezterm": {
    "env": "WEZTERM_EXECUTABLE",
    "command": "wezterm",
    "args": ["cli", "split-pane", "--right", "--", ["exe"] , ["args"], "--terminal"],
},
```

The `env` key specifies the name of an environment variable which Nev checks for existence to determine if it runs inside of a
terminal multiplexer.

`["exe"]` gets replaced with the path of the current Nev executable, `["args"]` gets replaced with some arguments Nev generates to open the session, which you need to forward.

### Example
If you select session `/home/my/project/.nev-session` in the recent session browser and you are running inside tmux,
then Nev will run the following command to launch the new session (the session argument comes from the `["args"]` substitution):

`tmux split-window nev --session=/home/my/project/.nev-session --terminal`

### Workspace

Session files contain the configuration of a [workspace](workspaces.md).

## Saving sessions

If you have a session then it will automatically save the session when closing the editor, otherwise nothing will be saved automatically.

## Creating a session file

Open the command line and use the command `save-session` to save the current editor state on disk.

You can also specify a session name like this: `save-session ".nev-session"`

`.nev-session` is the default session file that will be loaded when you run it without any arguments, so this name is recommended.
