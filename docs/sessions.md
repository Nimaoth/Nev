# Sessions

Sessions allow you to keep your editor state, even if you close it. That way you don't need to reopen all the same files again, or add breakpoints all over again.

You can see which session is currently used in the bottom right of the editor.

If you don't have a session it will say `[No Session]`, otherwise it will show the name of the session:  `[Session: .absytree-session]`

If you have a session file and want to modify it manually (e.g. to change workspace settings) then you should not edit the session file while you have that same session open, because once you exit the session file will be overridden.
Instead just edit it with `ast .absytree-session`.

## Using sessions

If you launch Absytree without a file as an argument then it will try to load a session from the default session file (`.absytree-session`) in the current working directory.

To use a different session you can use `-s` like this: `ast -s:foo.absytree-session`.

If you launch Absytree with a file path (like `ast foo.txt`) then it will only open that file, but not load a session.

### Workspace

Session files contain the configuration of a [workspace](workspaces.md). The recommended way to change workspace settings
is by modifying the session file and restarting the editor.

## Saving sessions

If you have a session then Absytree will automatically save the session when closing the editor, otherwise nothing will be saved automatically.

## Creating a session file

Open the command line and use the command `save-session` to save the current editor state on disk.

You can also specify a session name like this: `save-session ".absytree-session"`

`.absytree-session` is the default session file Absytree tries to load when you run it without any arguments, so this name is recommended.

Here is an example of a session file
```json
// .absytree-session
{
    // ...
    "workspaceFolders": [ // Although this is an array only one workspace is supported.
        {
            "kind": 0, // 0 - Local, 1 - AbsytreeServer
            "id": "663f8b0ad15f6f2f4922322a", // Generated automatically, but currently not really used
            "name": "My workspace", // Name, can be anything
            "settings": {
                "path": "/some/path", // Primary workspace folder
                "additionalPaths": [ // Additional folders which are available for e.g. choose-file command
                    "/some/other/path"
                ]
            }
        }
    ],
    "openEditors": [ // Which files you had open (and visible)
        {
            "filename": "/some/file.js",
            "languageID": "javascript",
            "appFile": false,
            "workspaceId": "663f8b0ad15f6f2f4922322a",
            "customOptions": { // Different kinds of editors can store their own state
                "selection": {
                    "first": {
                        "line": 1,
                        "column": 29
                    },
                    "last": {
                        "line": 1,
                        "column": 29
                    }
                }
            }
        }
    ],
    "hiddenEditors": [], // Which files you had open (but hidden)
    "commandHistory": [
        "set-search-query \\, ,",
        "save-session \".absytree-session\""
    ],
    "debuggerState": {
        "breakpoints": {
            "/some/other/file": [
                {
                    "path": "/some/other/file",
                    "enabled": true,
                    "breakpoint": {
                        "line": 61
                    }
                }
            ]
        }
    }
}
```
