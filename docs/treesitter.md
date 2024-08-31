# Treesitter

Treesitter is used for e.g. syntax highlighting.

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

## External parsers

Nev supports treesitter parser compiled to dynamic libraries (`.dll`/`.so`) or `wasm` modules.
`.dll`/`.so` parsers are not supported in the musl version because it can't load dynamic libraries, but `wasm` parsers are still supported.

The parsers have to placed in `{app_dir}/languages` to be detected.

## Installing external treesitter parsers

Treesitter parsers currently have to be installed manually (or you take them from another editor).
Parsers can be installed using the command `install-treesitter-parser`.
If `languages.xyz.treesitter` is set to a github repository name like `alaviss/tree-sitter-nim` then you can just
pass the language name to `install-treesitter-parser`. Otherwise you can pass the repository name directly.

`install-treesitter-parser` will clone the repository in `{app_dir}/languages/tree-sitter-xyz` and then compile the parser
to a `wasm` module.
This requires `git` and `emscripten` to be installed and in the `PATH`.

To see which languages have the treesitter repository preconfigured look at the [base settings](../config/settings.json)

```nim
install-treesitter-parser "nim" # Uses repo configured in `languages.nim.treesitter`
install-treesitter-parser "maxxnino/tree-sitter-zig" # username/repo-name
install-treesitter-parser "tree-sitter/tree-sitter-typescript/typescript" # Parser is in subdirectory `typescript` in the repository
```

## Configuration

There is not much to configure treesitter. By default the editor will look for the parser library in `{app_dir}/languages/{language}.{dll|so}`.

```json
// ~/.nev/settings.json
{
    // `+` is used to add new configurations instead of overriding all of them with just these
    "+treesitter": {
        "cpp": { // Add/override cpp settings
            // Setting the path is generally not required if you install the parser using `install-treesitter-parser`
            // or put the parser binary in `{app_dir}/languages`

            // On windows
            "path": "C:/path/to/cpp.dll",

            // On linux
            "path": "/path/to/cpp.so"
        }
    },
    "+languages": {
        "markdown": {
            // username/repo-name/subdir
            // subdir is required if the `src` directory containing the parser is not in the root of the repository
            "treesitter": "tree-sitter-grammars/tree-sitter-markdown/tree-sitter-markdown",

            // If there are multiple parsers in the same repository then you need to specify where the queries
            // for this parser are. If there is only one parser then it will find the queries by looking for the
            // `highlights.scm` file.
            "treesitter-queries": "tree-sitter-markdown/queries",

            "tabWidth": 2,
            "indent": "spaces",
            "blockComment": [ "<!--", "-->" ]
        }
    }
}
```
