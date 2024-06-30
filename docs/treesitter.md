# Treesitter

Treesitter is used for e.g. syntax highlighting.

**Currently highlight queries need to be customized for this editor as it maps the capture names
directly to the highlight id in the theme. Only the Nim and Cpp highlight queries are tested.**

## Builtin treesitter parsers

The editor can be statically linked to some treesitter parsers.
To add support for new builtin treesitter languages create a pull request [here](https://github.com/Nimaoth/nimtreesitter)

The list of builtin parsers is currently:
- C/C++
- Nim
- C#
- Rust
- Python
- Javascript

To change the list of builtin parsers compile the editor with e.g. `-d:treesitterBuiltins=cpp,rust`

If an external parser exists then the editor will not use the internal one.

## Install external treesitter parsers

Treesitter parsers currently have to be installed manually (or you take them from another editor).

External parsers are not supported in the musl version because it can't load dynamic libraries.

## Configuration

There is not much to configure treesitter. By default the editor will look for the parser library in `{app_dir}/languages/{language}.{dll|so}`.

```json
// ~/.absytree/settings.json
{
    // `+` is used to add new configurations instead of overriding all of them with just these
    "+treesitter": {
        "cpp": { // Add/override cpp settings
            // On windows
            "path": "C:/path/to/cpp.dll",

            // On linux
            "path": "/path/to/cpp.so"
        }
    }
}
```
