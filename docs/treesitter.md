# Treesitter

Treesitter is used for e.g. syntax highlighting.

## Builtin treesitter parsers

The editor is statically linked to some treesitter parsers.

The list of builtin parsers is currently:
- C/C++
- Nim
- C#
- Rust
- Python
- JavaScript
- JSON
- Markdown

To change the list of builtin parsers compile the editor with e.g. `-d:treesitterBuiltins=cpp,rust`

If an external parser exists then the editor will not use the builtin one.

## External parsers

Nev supports treesitter parser compiled to dynamic libraries (`.dll`/`.so`) or `wasm` modules.
`.dll`/`.so` parsers are not supported in the musl version because it can't load dynamic libraries, but `wasm` parsers are still supported.

The parsers have to placed in `{app_dir}/languages` to be detected.

## Installing external treesitter parsers

Treesitter parsers currently have to be installed manually (or you take them from another editor).
Parsers can be installed using the command `install-treesitter-parser`.
If `lang.xyz.text.treesitter.repository` is set to a github repository name like `alaviss/tree-sitter-nim` then you can just
pass the language name to `install-treesitter-parser`. Otherwise you can pass the repository name directly.

`install-treesitter-parser` will clone the repository in `{app_dir}/languages/tree-sitter-xyz` and then compile the parser
to a `wasm` module.
This requires `git` and `emscripten` to be installed and in the `PATH`.

To see which languages have the treesitter repository preconfigured look at the [base settings](../config/settings.json)

```nim
install-treesitter-parser "nim" # Uses repo configured in `lang.xyz.text.treesitter.repository`
install-treesitter-parser "maxxnino/tree-sitter-zig" # username/repo-name
install-treesitter-parser "tree-sitter/tree-sitter-typescript/typescript" # Parser is in subdirectory `typescript` in the repository
```

## Configuration

There is not much to configure treesitter. By default the editor will look for the parser library in `{app_dir}/languages/{language}.{dll|so}`.

```json
// ~/.nev/settings.json
{
    "lang.markdown.text.treesitter": {
        // username/repo-name/subdir
        // subdir is required if the `src` directory containing the parser is not in the root of the repository
        "repository": "tree-sitter-grammars/tree-sitter-markdown/tree-sitter-markdown",

        // If there are multiple parsers in the same repository then you need to specify where the queries
        // for this parser are. If there is only one parser then it will find the queries by looking for the
        // `highlights.scm` file.
        "queries": "tree-sitter-markdown/queries",
    }
}
```
