# Cheatsheet

By default the vim keybindings are used.
The vim keybindings are not complete yet and will never be as this editor is not exactly the same as Vim. But if anything is missing please open an issue.

There are also incomplete VSCode like keybindings.
To switch to VSCode like keybindings create/extend the config file in `<USER_HOME>/.nev/settings.json` with the following:
```json
{
  "keybindings": "vscode"
}
```

Possible values for `keybindings`: `vscode`, `vim` (default)

After changing the settings restart the editor.

## Most important keybindings (C: Control, A: Alt, S: Shift)

| Description | Vim | VSCode |
| ----------- | --- | ------ |
| Open command line | `<LEADER><LEADER>` or `:` | `<CS-p>` or `<F1>` |
| Help | `<LEADER>gh` | `<C-g>h` |
| Find file in workspace | `<LEADER>gf` | `<C-g>f` or `<C-p>` |
| Find open file | `<LEADER>go` | `<C-g>o` |
| File explorer for entire workspace | `<LEADER>ge` | `<C-g>e` |
| File explorer for primary workspace folder | `<LEADER>gw` | `<C-g>w` |
| File explorer for app config | `<LEADER>ga` | `<C-g>a` |
| File explorer for user config | `<LEADER>gu` | `<C-g>u` |
| Global search in workspace | `<LEADER>gs` | `<C-g>s` or `<CS-f>` |
| Git changes | `<LEADER>gg` | `<C-g>g` |
| Save file | `<LEADER>sf` | `<C-s>` |
| Reload file from disk | `<LEADER>lf` | |
| Close popups, command line, etc | `<ESCAPE>` | `<ESCAPE>` |
| Quit the editor | `<C-x><C-x>` | `<A-F4>` |

## Window navigation

For the following keybindings which start with `<C-w>` you can also use `<LEADER>w` instead,
so e.g. `<C-w>x` and `<LEADER>wx` both work

| Description | Vim | VSCode |
| ----------- | --- | ------ |
| Close current view | `<C-w>q` | `<C-w>q` |
| Hide current view | `<C-w>x` | `<C-w>x` |
| Focus previous view | `<C-w><LEFT>` or `<C-w>h` | `<C-w><LEFT>` or `<C-w>h` |
| Focus next view | `<C-w><RIGHT>` or `<C-w>l` | `<C-w><RIGHT>` or `<C-w>l` |
| Move current view to previous | `<C-w>H` | `<C-w>H` |
| Move current view to next | `<C-w>L` | `<C-w>L` |
| Toggle fullscreen for current view | `<LEADER>m` |  |

## Most important commands (most of these have keybindings, see above and [browse-keybinds](finders.md#browse-keybinds))
- `help`: Show the documentation
- `explore-help`: Browse all documentation files
- `create-file "path/to/filename.xyz"`: Create and open a file with the specified path.
- [`choose-file`](finders.md#choose-file): Search for a file in all workspace folders.
- [`choose-open`](finders.md#choose-open): Search for a file in open files.
- [`choose-git-active-files`](finders.md#choose-git-active-files): Shows changed/added/deleted/untracked git files with a diff preview.
- [`explore-files`](finders.md#explore-files): Open a file explorer for all workspace folders.
- [`explore-workspace`](finders.md#explore-workspace): Open a file explorer for the primary workspace folder.
- [`explore-user-config`](finders.md#explore-user-config): Search for config files in the user directory.
- [`explore-app-config`](finders.md#explore-app-config): Search for config files that are installed with the editor.
- [`browse-keybinds`](finders.md#browse-keybinds): Search through current keybindings.
- `logs`: show the log file
- `load-normal-keybindings`: load "normal" keybindings (like vs code)
- `load-vim-keybindings`: load vim keybindings (WIP). As close to vim as possible.