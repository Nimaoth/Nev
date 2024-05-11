- add auto completion to textdocument for command line

- x86_64-w64-mingw32-gcc -print-file-name=libstdc++.a

## General stuff
- horizontal scrolling
- detect indentation from file content
- improve indentation handling to auto fix incorrect indentation
- implement marks
- add command to restart languageserver
- fix choose cursor mode interaction with command recording
- add options for trimming trailing whitespace on save (e.g. only for certain file types, enable/disable, keybinding?)
- render indentation guides
- text folding
- improve scrolling when mouse is pressed and extending selection
- make double/triple click work in browser/terminal
- command for switching first and last cursor
- command for switching active selection

- add language server/treesitter for markdown/help files

- implement text decorations api for scripting (inserting virtual text, replacing text)

- get [https://github.com/treeform/vmath/pull/67] merged and change vmath back to original repo
- finish [https://github.com/tree-sitter/tree-sitter/pull/2091]

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

## Vim Keybindings
- Repeat f/t motions with ,/;
- Search/Replace
- toggle case
- fix e.g. dw deleting one character to much because it's inclusive

- in visual mode highlights are incorrect
- pasting text replaces the current char even if not in insert mode
- fix f/t not working with uppercase characters

- fix:
  - go into insert mode
  - switch to different view
  - keeps recording into .

## LSP
- Handle rust lsp paths with lowercase letter like d:/path/to/file
- command for inserting the inlay hint under the cursor
- snippets
- workspace symbols
- rename
- inlay hints: space left/right

## text editor
- includeAfter names should be named includeLineLen or something like that
- don't render multi line diagnostics inline but in a popup which can be opened/closed
- don't show completion window when no completions available
- read file when on disk changes, e.g. after revert
- don't send lsp close event until document is closed, not just editor/staged diff editor

- terminal undercurl/underline:
  - debug "\e[4munderline\e[0m"
  - debug "\e[58:2::255:192:203m\e[4:3mCheck out this cool sentence with colorful curly lines!\e[m"
  - debug "\e[58:2::255:192:203m\e[4:2mCheck out this cool sentence with colorful double lines!\e[m"
  - debug "\e[58:2::255:0:0m\e[4:2mCheck out this cool sentence\e[4:3m with a bunch\e[58:2::135:206:235m of lines styles \e[4:5mand colors!\e[m"

- it looks like if you try to updated completions before the language server is initialized, then it might not initialize at all?
