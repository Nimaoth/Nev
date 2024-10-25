# Virtual file system (VFS)

Nev uses a virtual file system internally. The VFS is a tree of different types of file systems (local, in-memory, remote, etc.).

Here are the types of file systems that are supported:
- `VFS` - The base type for all other file systems, which can be used as a container/folder for other VFSs.
- `VFSInMemory` - This file system stores files in RAM.
- `VFSLocal` - This represents your local filesystem.
- `VFSLink` - This file system can link into a subfolder of another file systems. Cycles are not allowed.

By default Nev creates a VFS hierarchy which contains the local file system under `local://`, and some links into that for convenience:
- `app://` links to the directory when Nev is installed under `local://`
- `home://` links to the user home directory under `local://`
- `ws0://`, `ws1://` etc. link to the workspace folders.
- `ws://0`, `ws://1` etc. link to the workspace folders.
- `plugs://`, contains plugin sources (if available)

To explore the entire VFS in the builtin file explorer you can run the command `explore-file "" true` (to see some more info about the VFSs) or just `explore-files`

![alt](https://raw.githubusercontent.com/Nimaoth/AbsytreeScreenshots/main/vfs.png)

You can see the also VFS hierarchy by running the command `dump-vfs-hierarchy`, which will output something like this:
```
VFS()
  '' -> VFSLink(, VFSLocal(local://)/)
  'local://' -> VFSLocal(local://)
  'app://' -> VFSLink(app://, VFSLocal(local://)//home/xyz/Nev)
  'plugs://' -> VFS(plugs://)
    'keybindings_plugin' -> VFSInMemory(keybindings_plugin)
    'my_plugin' -> VFSInMemory(my_plugin)
  'ws://' -> VFS(ws://)
    '0' -> VFSLink(0, VFSLocal(local://)//home/xyz/my project)
  'home://' -> VFSLink(home://, VFSLocal(local://)//home/xyz)
  'ws0://' -> VFSLink(ws0://, VFSLocal(local://)//home/xyz/my project)
```
Here is a visual representation.

![VFS graph](https://raw.githubusercontent.com/Nimaoth/AbsytreeScreenshots/main/graph.png)

With the given VFS, the following paths would refer to these files:

| VFS Path                    | Normalized path        | Explanation |
| -------------------------   | -------------- | - |
| `local:///home/xyz/Nev/nev.exe`        | `local:///home/xyz/Nev/nev.exe`       | The `local://` prefix refers to a VFSLocal, which itself doesn't link to other VFSs. |
| `/home/xyz/Nev/nev.exe`                | `local:///home/xyz/Nev/nev.exe`       | This path doesn't match any of the prefixes of the form `xyz://`, but it does match the VFSLink with an empty prefix, which in turn links to the VFSLocal |
| `home://Nev/nev.exe`        | `local:///home/xyz/Nev/nev.exe`       | The `home://` prefix refers to `local:///home/xyz`, add to that `Nev/nev.exe` |
| `app://nev.exe`        | `local:///home/xyz/Nev/nev.exe`       | The `app://` prefix refers to `local:///home/xyz/Nev`, add to that `nev.exe` |
| `ws0://foo.txt`        | `local:///home/xyz/my project/foo.txt`       | The `ws0://` prefix refers to `local:///home/xyz/my project`, add to that `foo.txt` |
| `ws://0/foo.txt`        | `local:///home/xyz/my project/foo.txt`       | The `ws://` prefix refers to a sub VFS, and in there the `0` prefix refers to `local:///home/xyz/my project`, add to that `foo.txt` |
| `plugs://keybindings_plugin/src.nim`        | `plugs://keybindings_plugin/src.nim`       | The `plugs://` prefix refers to a sub VFS, and in there the `keybindings_plugin` prefix refers to an in memory VFS |

## Mounting VFSs

The `mount-vfs` command can be used to mount new VFSs in the VFS hierarchy:

```
mount-vfs <parent vfs path> <prefix within parent> <vfs config>
```

## Examples

### Mount the nimble packages directory under `nimble://` to have quick access to nim library source code:
```json
// ~/.nev/settings.json
{
    "+wasm-plugin-post-load-commands": [ // Run these commands after loading wasm plugins
        [
            "mount-vfs",
            null, // Null means mount under the root. If a path is provided then it will be mounted under the VFS the given path resolves to.
            "nimble://", // The prefix under which to mount the new VFS
            { // VFS description
                "type": "link", // create a VFSLink
                "target": "home://", // path of the target VFS to link to
                "targetPrefix": ".nimble/pkgs2" // Subdirectory within the target VFS
            }
        ]
    ]
}
```
After running this command the path `nimble://package_name/package.nim` would refer to `home://.nimble/pkgs2/package_name/package.nim`, which in turn refers to `local:///home/xyz/.nimble/pkgs2/package_name/package.nim`

### Mount a local folder as plugin source.
The `browse-keybinds` finder shows you the source code which defined keybindings (if available). It reads this source code from `plugs://<plugin_name>/<source_file>.nim`, which by default is mounted as an in memory VFS, containing embedded source code from the wasm binary.

If you develop you're own plugin you might want that to link to you're source code on your local file system instead.

To do this you can remount the filesystem for your plugin like this:
```json
// ~/.nev/settings.json
{
    "+wasm-plugin-post-load-commands": [ // Run these commands after loading wasm plugins
        [
            "mount-vfs",
            "plugs://", // Mount the new VFS under the VFS with the prefix 'plugs://'
            "my_plugin", // The prefix under which to mount the new VFS
            { // VFS description
                "type": "link", // create a VFSLink
                "target": "local://", // path of the target VFS to link to, you could also use app:// or home:// or whatever.
                "targetPrefix": "/path/to/plugin/source" // Subdirectory within the target VFS
            }
        ]
    ]
}
```
After running this command the path `plugs://my_plugin/source.nim` would not refer to the in-memory VFS anymore but to `local:///path/to/plugin/source/source.nim` instead.
