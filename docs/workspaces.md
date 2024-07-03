# Workspaces

A workspace represents one or more directories of your project.

Every time you open Absytree it will create a workspace. By default this will be a local workspace for the current working directory.
If you use a session then the session defines the workspace instead.

There are different kinds of workspaces:
- Local: This workspace allows you to directly access local files.
- AbsytreeServer: This is a remote workspace, so you need to run a server somewhere and then Absytree will connect to that server to access the file system.
- Github (readonly): This workspace uses a Github repository to download files.

For now only the local workspace is ready for use (although you can see the Github workspace in action in the browser demo).

To configure your workspace you need to create a [session](sessions.md) and edit workspace settings in the session file.

Here is an except from a session file:
```json
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
    ]
}
```
