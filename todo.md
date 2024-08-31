- add auto completion to textdocument for command line

- x86_64-w64-mingw32-gcc -print-file-name=libstdc++.a

## General stuff
- horizontal scrolling
- improve indentation handling to auto fix incorrect indentation
- implement marks
- add command to restart languageserver
- fix choose cursor mode interaction with command recording
- add options for trimming trailing whitespace on save (e.g. only for certain file types, enable/disable, keybinding?)
- text folding
- command for switching first and last cursor
- command for switching active selection

- implement text decorations api for scripting (inserting virtual text, replacing text)

- get [https://github.com/treeform/vmath/pull/67] merged and change vmath back to original repo
- finish [https://github.com/tree-sitter/tree-sitter/pull/2091]

## Vim Keybindings
- Repeat f/t motions with ,/;
- Search/Replace

- in visual mode highlights are incorrect
- pasting text replaces the current char even if not in insert mode

## LSP
- command for inserting the inlay hint under the cursor
- rename
- inlay hints: space left/right

## text editor
- includeAfter names should be named includeLineLen or something like that
- don't render multi line diagnostics inline but in a popup which can be opened/closed
- don't show completion window when no completions available
- read file when on disk changes, e.g. after revert

- terminal undercurl/underline:
  - debug "\e[4munderline\e[0m"
  - debug "\e[58:2::255:192:203m\e[4:3mCheck out this cool sentence with colorful curly lines!\e[m"
  - debug "\e[58:2::255:192:203m\e[4:2mCheck out this cool sentence with colorful double lines!\e[m"
  - debug "\e[58:2::255:0:0m\e[4:2mCheck out this cool sentence\e[4:3m with a bunch\e[58:2::135:206:235m of lines styles \e[4:5mand colors!\e[m"

# Linux clipboard support
- copy: `xclip -i -selection clipboard`
- paste: `xclip -o -selection clipboard`

# Build windows with vcc
- `nimble --nimbleDir:D:/nd -d:debugDelayedTasks -d:debugAsyncAwaitMacro buildDebugVcc`
- `cl.exe @nev_linkerArgs.txt D:\nd\pkgs2\nimwasmtime-0.1.5-95eac5c2bb83073e089b1c21d35e5db76d969f2d\wasmtime\target\release\wasmtime.dll.lib /LINK Advapi32.lib`
- `nevd.exe -s:debug.nev-session`


# AST language framework
- add nicer way to write:
  - StringGetPointer, StringGetLength
  - <, <=, etc
- add bool type
- make [] work with strings
- add char literal
- add string escape and/or allow entering \n
- auto open completion window?
- auto accept completion exact match even if other/longer completions exist
- render actual types in type placeholders
- add text based search (fuzzy?)
- add validation for all ast node types
- allow deleting selection in e.g. property cells
- make node reference not editable
- don't allow node substitution keys on empty expressions
- improve auto parenthesis for cells
- add struct scoped functions
- support copying multiple nodes
- fix deleting e.g struct member type bug
- negative number literal, float literal
- render cell indentation guides
- invalidate models using language X when X gets rebuilt
- finish/revise using string as parameter type for wasm functions (see createWasmWrapper, createHostWrapper)
- fix potential issues because of loading order when loading test-language and test-language-playground
- git: use workspace directory instead of working directory
- make sure that after every await in text editor/model editor we check if the editor has beeen deinitialized
- named UI nodes are never cleaned up
- use github raw link for github workspace
- move git stuff to workspace to support multiple git repositories
- global search:
  - figure out how to specify file filters and other options (case sensitive, whole word match, regex)