# Workspace

The workspace is a list of directories which are part of you're project.<br>
The workspace affects features like global search, the file selector etc. These will show/search files in all workspace directories.

Every time you open the editor it will create a workspace. By default this will be the current working directory.
If a session is opened then the session defines the workspace instead.

To add directories to you're workspace you can either edit the session file or use the virtual file system explorer (see below).<br>
When you add a directory to your workspace then it will be mounted in the VFS under a prefix like `ws5://` (each directory has a distinct number).

**If you edit a session file while you have that session open then your changes will be override when you close Nev**

Here is an example from a session file. You can add directories to "additionalPaths":
```json
{
    // ...
    "workspaceFolder": {
        "name": "My workspace", // Name, can be anything
        "settings": {
            "path": "/some/path", // Primary workspace folder
            "additionalPaths": [ // Additional folders which are available for e.g. choose-file command
                "/some/other/path"
            ]
        }
    }
}
```

## Add/Remove workspaces using the VFS explorer

To add a directory to your workspace:
1. Open the vfs explorer using either the command `explore-files` or by pressing `SPACE gv`
2. Navigate to the directory you want to add to your workspace and select it using `C-p` and `C-n`
3. Press `C-a` to add the selected directory to you're workspace

To remove a directory from you're workspace:
1. Open the VFS explorer
2. Select the workspace you want to delete (workspace folders look like `ws0`, `ws1` etc)
3. Press `C-x`
