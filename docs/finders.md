# Finders

Finders allow you to use fuzzy search through all kinds of things.
- Files on disk
- Open files
- Modified/untracked/etc git files
- Themes
- Install/global/workspace config files
- Document/workspace symbols, references, etc.
- and more

Some finders also show previews. By default `<TAB>` switches input focus between the finders search bar and the preview editor.

While a finder is open the following keybinding contexts are pushed:
- `editor.text`: The search bar
- `popup.selector`: General finder keybindings
- `popup.selector.xyz`: Specific finder keybindings. `xyz` is an identifer that identifies a specific kind of finder (e.g. `git` for `choose-git-active-files`)

When the preview is focused the following contexts are pushed instead:
- `editor.text`: The preview editor
- `editor.selector.preview`: For overriding keybindings of the text editor while in a preview

Default keybindings:
- Vim:
  - `<C-n>` or `<DOWN>`: Select next entry.
  - `<C-p>` or `<UP>`: Select previous entry.
  - `<C-y>` or `<ENTER>`: Confirm selection. Behaviour depends on the specific finder.
  - `<ESCAPE>`: Close the finder.
- VSCode:
  - `<DOWN>`: Select next entry.
  - `<UP>`: Select previous entry.
  - `<ENTER>`: Confirm selection. Behaviour depends on the specific finder.
  - `<ESCAPE>`: Close the finder.

The finder API is currently not exposed to plugins yet, but will be in the future, so plugins will be able to create
custom finders to fuzzy search/find anything.

## `choose-file`
### Custom context: `popup.selector.file`
Search for a file in all workspace folders.

## `choose-open`
### Custom context: `popup.selector.open`
Search for a file in open files.

## `choose-git-active-files`
### Custom context: `popup.selector.git`

Shows changed/added/deleted/untracked git files with a diff preview.
It takes one bool argument `all`:
- `choose-git-active-files true`: Show files from all git repositories in all workspace folders
- `choose-git-active-files false`: Show files from the primary git repository

The entries are prefixed with a two character code (e.g. `.M`).
The first character character is the staged status, the second one is the unstaged status.
The following characters exist:
- `.`: unchanged
- `M`: modified
- `A`: added
- `D`: deleted
- `?`: not part of the repository

Once you stage for example a modified file with the status `.M`, there will be two
entries for that file, one with `M.` which represents the staged version and one with `..` which represents the unstaged file.
As soon as you add more changes to that file `..` will become `.M` to show that it contains new changes.
If you don't intend to add more changes you can ignore it.

Custom commands:
- `stage-selected` (default: `<C-a>`): Stages the selected file
- `unstage-selected` (default: `<C-u>`): Unstages the selected file
- `revert-selected` (default: `<C-r>`): Reverts the selected file

The following GIF shows an example of using this command after making some modifications to a file.

![alt](https://raw.githubusercontent.com/Nimaoth/AbsytreeScreenshots/main/git.gif)

## `explore-files <path>`
### Custom context: `popup.selector.file-explorer`
Open a file explorer in the selected directory. The path is a path in the virtual file system.

Examples:
- `explore-files "app://config"` - Explore config files that are installed with the editor.
- `explore-files "home://.nev"` - Explore config files in the user home directory.
- `explore-files "ws0://"` - Explore files in first workspace folder.
- `explore-files ""` - Explore the root of the VFS.

Custom commands:
- `go-up` (default: `<C-UP>` or `<C-r>`): Go to parent directory
- `add-workspace-folder` (default: `<C-a>`): Add to selected folder to the workspace
- `remove-workspace-folder` (default: `<C-x>`): Remove the selected folder from the workspace

The default confirm behaviour is to enter folders and open files.
The preview shows the file content for files and the list of sub files/folders for folders.

![alt](https://raw.githubusercontent.com/Nimaoth/AbsytreeScreenshots/main/explore-files.png)

## `explore-workspace`
### Custom context: `popup.selector.file-explorer`
Open a file explorer for the primary workspace folder.
Same usage as `explore-files`

## `explore-user-config`
### Custom context: `popup.selector.file-explorer`
Explore config files in the user directory.
Same usage as `explore-files`

## `explore-app-config`
### Custom context: `popup.selector.file-explorer`
Explore config files that are installed with the editor.
Same usage as `explore-files`

## `explore-workspace-config`
### Custom context: `popup.selector.file-explorer`
Explore config files in the workspace primary workspace folder.
Same usage as `explore-files`

## `explore-help`
### Custom context: `popup.selector.file-explorer`
Open a file explorer for the builtin docs (what you're reading right now).

## `browse-keybinds`

This command opens a finder which allows you to search through the list of all keybindings by command or key combination.
The columns are:
- Description of the command (or name if no description exists)
- Key combination
- Context
- Raw command that will be executed

![alt](https://raw.githubusercontent.com/Nimaoth/AbsytreeScreenshots/main/browse-keybinds-command.png)

To search for a key combination simply prefix the search with `|`. This isn't strictly necessary but will improve search results.
![alt](https://raw.githubusercontent.com/Nimaoth/AbsytreeScreenshots/main/browse-keybinds-key.png)

## `browse-settings`

This command opens a finder which allows you to search through all settings currently known (settings are known if some feature reads/writes the value of the setting)
If the setting is a boolean you can toggle it with `<C-t>`. Other settings can be changed by changing the value in th
preview and saving.
