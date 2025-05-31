- add auto completion to textdocument for command line

- x86_64-w64-mingw32-gcc -print-file-name=libstdc++.a

## General stuff
- improve indentation handling to auto fix incorrect indentation
- add command to restart languageserver
- fix choose cursor mode interaction with command recording
- text folding
- command for switching active selection
- command for aligning cursors
- fuzzy matching with a single character somewhere in the string should result in a positive score

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

## text editor
- includeAfter names should be named includeLineLen or something like that
- don't render multi line diagnostics inline but in a popup which can be opened/closed
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
- Named UI nodes are never cleaned up
- Use GitHub raw link for GitHub workspace
- move git stuff to workspace to support multiple git repositories
- global search:
  - figure out how to specify file filters and other options (case sensitive, whole word match, regex)

- show aliases in command line auto complete.

- fix multiple code actions for the same diagnostic
- code action sorting

- slicing a rope slice does't work

- disable tab for switching preview focus for terminal selector
- add support for line numbers (`path:line`, `path:line:column`, `path(line, column)`, etc) in goto-definition of path language server
- add path language server to terminal output
- add scrollback buffer to terminal output rope
- fix whitespace rendering when running `git commit`
