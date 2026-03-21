# Moves

Moves define how cursors and selections navigate text in Nev. They are used in keybindings and various other features. Moves are written as **Lisp s-expressions** -- a chain of transformation functions applied sequentially to a list of selections.

## The Lisp DSL

Moves are written as parenthesized expressions where each form is a function call that transforms the current **list of selections**. Forms are evaluated left to right, each receiving the output of the previous one.

Every move operates on a list of selections (which may contain just one). There are two kinds of moves:

- **Per-selection moves** transform each selection individually. For example, `column` moves every cursor left or right, and `grow` expands every selection. The number of selections stays the same.
- **Whole-list moves** operate on the entire list at once and can change the number of selections. For example, `split` breaks multi-line selections into one selection per line, `combine` merges all selections into one, and `first` discards all but the first selection.

```lisp
(line) (start)
```

This first applies `line` (selects the entire current line), then `start` (moves the cursor to the start of that selection).

Functions with arguments use standard Lisp syntax:

```lisp
(column 1)           ;; move cursor 1 column right
(line-num 42)        ;; go to line 42
(surround "{" "}")   ;; select surrounding braces
```

### How moves work

Moves are **side effects**: each move function mutates a temporary list of selections maintained by the editor, but does **not** return the new selections as a lisp value. The selections live outside the lisp environment. The lisp expression `(line)` changes that selection list and returns `nil`. This is why chaining works -- `(line) (start)` runs `(line)` (which selects the line), then `(start)` (which moves to the start of whatever selections now exist). Nesting `(start (line))` is equivalent because the evaluator runs `(line)` first as a side effect, then runs `(start)`.

This also means **you cannot read or manipulate raw selection positions from lisp**. The selection list (line numbers, columns, ranges) is not exposed as lisp data. There is no way to get the current line number or column as a lisp value and do arithmetic on it. Raw cursor positions are handled internally by the editor. The lisp DSL is a composition language for combining existing named moves, not a general-purpose cursor API. You build behavior by composing moves like `(line-num 42)`, `(column 1)`, `(surround "{" "}")`, `(grow 1)`, etc. -- each of which encapsulates a specific cursor transformation.

### Nesting moves

Moves can be chained either by writing them sequentially or by nesting one inside another:

```lisp
(line) (start)          ;; select the line, then move to its start
(start (line))          ;; same thing: (line) runs first as the inner form
```

In both cases `(line)` runs first, then `(start)`. Nesting is equivalent to sequencing because the lisp evaluator evaluates inner forms before outer ones.

**Important: argument order matters.** Move functions receive their arguments in positional order, and nested forms produce argument values. Moves do not return meaningful lisp values, so if a nested move ends up in an argument slot, the argument will get a useless value (`nil`). Always put nested moves **after** all explicit arguments:

```lisp
(line-down) (column 1)               ;; good: go one line down, then one column to the right
(column (line-down))                 ;; bad: line-down's return value (nil) is passed as the DIR argument
(column 1 (line-down))               ;; good: 1 is the DIR argument, (line-down) still gets evaluated before column, but column only uses the first argument
```

The same applies to moves with optional arguments -- if you omit an argument and place a nested move in that position, the nested move's return value fills the argument slot instead of the default:

```lisp
(column 1) (line-up)                  ;; good: column with explicit DIR, then line-up
(column (line-up))                    ;; bad: line-up's return value (nil) becomes DIR
```

### Branching and conditionals

The DSL supports `if`, `let`, arithmetic, and comparison:

```lisp
(if (eq c 0) (start (file)) (start (line-no-indent (line-num (- c 1)))))
; Or without nesting (notice the 'list' used to run moves sequentially)
(if (eq c 0) (list (file) (start)) (list (line-num (- c 1)) (line-no-indent) (start)))
```

### Available DSL functions

These are built-in functions in the move language that operate on the current selection list:

| Function | Scope | Description |
|---|---|---|
| `(original)` | list | Reset selections to what they were before the move chain started |
| `(push)` | list | Push current selections onto a stack |
| `(pop)` | list | Pop selections from the stack, replacing current ones |
| `(discard)` | list | Pop selections from the stack and discard them. |
| `(first)` | list | Keep only the first selection (discard the rest) |
| `(last)` | list | Keep only the last selection |
| `(nth N)` | list | Keep only the Nth selection (0-indexed, negative indexes from end) |
| `(start)` | per-selection | Move each cursor to the start of its selection |
| `(end)` | per-selection | Move each cursor to the end of its selection |
| `(count*)` | env | Multiply the current repeat count by N |
| `(count= N)` | env | Set the current repeat count to N |
| `(merge)` | per-selection | Merge each new selection with the corresponding original selection (union of ranges) |
| `(join [start-sel] [end-sel])` | per-selection | Reconstruct each selection by combining start from one source and end from another (see below) |
| `(same?)` | query | Returns true if selections are unchanged from original |

**Scope** key: *per-selection* = applied to each selection individually, *list* = operates on the entire list and can change the selection count, *env* = modifies environment state, *query* = read-only check.

### Lisp primitives

These are general-purpose Lisp functions and special forms available in the DSL:

| Form | Description |
|---|---|
| `(let NAME EXPR)` | Bind a value to a name for use in subsequent expressions |
| `(if COND THEN [ELSE])` | Conditional evaluation. `COND` is truthy if non-zero and non-nil |
| `(eq A B)` | Returns true if A and B are equal |
| `(or A B ...)` | Returns the first truthy argument, or the last argument if none are truthy |
| `(floor N)` | Round N down to the nearest integer |
| `(+ A B ...)`, `(- A B)`, `(* A B ...)`, `(/ A B)` | Arithmetic: add, subtract, multiply, divide |
| `(> A B)`, `(< A B)` | Numeric comparison |

### Cursor selectors for `join`

The `(join ...)` function takes optional selector arguments to build new selections from different points in the move chain:

- `orig-start` / `orig-end` -- start/end of the original selection (before the move)
- `last-start` / `last-end` -- start/end of the selection after the previous move
- `curr-start` / `curr-end` -- start/end of the current selection
- `.` -- use the default (original-start for first arg, current-end for second arg)

## Text object keybindings

### Vim text objects (`vim#text_object`)

| Key | Move | Description |
|---|---|---|
| `iw` | `(vim.word-inner) (inclusive)` | Inner word |
| `aw` | `(vim.word-inner) (inclusive)` | A word (currently same as inner word) |
| `iW` | `(vim.WORD-inner) (inclusive)` | Inner WORD (non-whitespace chunk) |
| `aW` | `(vim.WORD-inner) (inclusive)` | A WORD |
| `ip` | `(vim.paragraph-inner) (inclusive)` | Inner paragraph |
| `ap` | `(vim.paragraph-outer) (inclusive)` | A paragraph |
| `ia` | `(ts 'call.inner') (overlapping) (last) (grow -1) (inclusive)` | Inner argument (tree-sitter) |
| `aa` | `(ts 'call.inner') (overlapping) (last) (inclusive)` | An argument (tree-sitter) |
| `ic` | `(ts 'call.outer') (overlapping) (last) (inclusive)` | Inner call (tree-sitter) |
| `ie` / `ae` | `(ts 'parameter.inner') (overlapping) (last) (inclusive)` | Inner/outer parameter (tree-sitter) |
| `i{`, `a{`, `i}`, `a}` | `(surround "{" "}" true/false)` | Inner/outer curly braces |
| `i(`, `a(`, `i)`, `a)` | `(surround "(" ")" true/false)` | Inner/outer parentheses |
| `i[`, `a[`, `i]`, `a]` | `(surround "[" "]" true/false)` | Inner/outer brackets |
| `i\<`, `a\<`, `i\>`, `a\>` | `(surround "<" ">" true/false)` | Inner/outer angle brackets |
| `i"`, `a"` | `(surround "\"" "\"" true/false)` | Inner/outer double quotes |
| `i'`, `a'` | `(surround "'" "'" true/false)` | Inner/outer single quotes |

## All moves reference

### Navigation moves

All navigation moves are **per-selection** -- they transform each selection individually without changing the count.

| Move | Arguments | Description |
|---|---|---|
| `column` | `(column DIR)` where DIR is 1 or -1 | Move cursor left (-1) or right (1) by count columns. Wraps across lines by default (controlled by `wrap` env var). |
| `line-up` | | Move cursor up count lines, preserving screen column |
| `line-down` | | Move cursor down count lines, preserving screen column |
| `visual-line-up` | | Move cursor up one visual (wrapped) line |
| `visual-line-down` | | Move cursor down one visual (wrapped) line |
| `visual-page` | | Move by a percentage of the screen height |
| `line-num` | `(line-num N)` | Go to line number N (0-indexed) |
| `line-start` | | Move cursor to column 0 of the current line |
| `target-column` | | Move cursor to the remembered target column |
| `move-to` | `(move-to CHAR)` | Find next occurrence of CHAR on the current line |

### Selection moves

| Move | Scope | Arguments | Description |
|---|---|---|---|
| `line` | per-selection | | Select the entire current line |
| `visual-line` | per-selection | | Select the current visual (wrapped) line |
| `file` | list | | Select the entire file (returns a single selection) |
| `line-no-indent` | per-selection | | Select from first non-whitespace character to end of line |
| `word-line` | per-selection | | Like `vim.word` but crosses line boundaries at line start/end |
| `word-line-back` | per-selection | | Like `vim.word-back` but crosses line boundaries |
| `grow` | per-selection | `(grow DIR)` | Expand/shrink selection by DIR characters on each side. Negative shrinks. |
| `number` | per-selection | | Select the number under the cursor (including leading `-`) |
| `surround` | per-selection | `(surround OPEN CLOSE [INSIDE])` | Select surrounding pair. Auto-detects bracket type if no args. |
| `inclusive` | per-selection | | Adjust selection: move end one column left (for vim inclusive operations) |
| `split` | list | | Split multi-line selection into per-line selections. Can increase the selection count. |

### Vim word motions

All vim word motions are **per-selection**.

| Move | Description |
|---|---|
| `vim.word` | Move to next word (alphanumeric/underscore group, or punctuation group) |
| `vim.word-back` | Move to previous word |
| `vim.WORD` | Move to next WORD (any non-whitespace) |
| `vim.word-inner` | Select current word (no trailing whitespace) |
| `vim.WORD-inner` | Select current WORD |
| `vim.paragraph-inner` | Select current paragraph (inner) |
| `vim.paragraph-outer` | Select current paragraph (outer, including blank lines) |

### Filtering and combining

| Move | Scope | Description |
|---|---|---|
| `reverse` | per-selection | Reverse each selection's direction (swap first and last) |
| `norm` | per-selection | Normalize each selection (ensure first <= last) |
| `combine` | list | Merge all selections into a single selection covering their union |
| `overlapping` | list | Keep only selections that overlap with the original cursor position |
| `non-overlapping` | list | Keep only selections that do not overlap with the original cursor position |
| `remove-empty` | list | Remove selections that have zero width |
| `align` / `align-right` | list | Move all cursors to the rightmost column among them |
| `align-left` | list | Move all cursors to the leftmost column among them |

### Search and diagnostic moves

| Move | Scope | Arguments | Description |
|---|---|---|---|
| `next-search-result` | per-selection | `(next-search-result [COUNT] [WRAP])` | Move to the next search result. COUNT is how many results to skip (default 0). WRAP wraps around the document (default true). |
| `prev-search-result` | per-selection | `(prev-search-result [COUNT] [WRAP])` | Move to the previous search result. Same arguments as `next-search-result`. |
| `next-change` | per-selection | | Move to the next VCS change |
| `prev-change` | per-selection | | Move to the previous VCS change |
| `next-diagnostic` | per-selection | `(next-diagnostic [SEVERITY] [COUNT] [WRAP])` | Move to the next diagnostic. SEVERITY filters by level (default 0 = all). COUNT skips that many results. WRAP wraps around (default true). |
| `prev-diagnostic` | per-selection | `(prev-diagnostic [SEVERITY] [COUNT] [WRAP])` | Move to the previous diagnostic. Same arguments as `next-diagnostic`. |

### Tree-sitter moves

| Move | Scope | Arguments | Description |
|---|---|---|---|
| `ts` | per-selection | `(ts CAPTURE [TRANSFORM])` | Select tree-sitter text object by capture name. E.g. `(ts 'call.inner')` selects function call arguments. An optional transform move is applied to the captured selections. Defaults to `(combine)` if no transform is given. |
| `ts-text-object` | per-selection | `(ts-text-object CAPTURE [TRANSFORM])` | Alias for `ts`. |
| `ts-tags-next` | per-selection | `(ts-tags-next [REGEX] [TRANSFORM])` | Move to the next tree-sitter tag match. Optionally filter by capture name regex. Defaults transform to `(first)`. Returns original selection if no match found. |
| `ts-tags-prev` | per-selection | `(ts-tags-prev [REGEX] [TRANSFORM])` | Move to the previous tree-sitter tag match. Optionally filter by capture name regex. Defaults transform to `(last)`. Returns original selection if no match found. |

### Other moves

| Move | Scope | Description |
|---|---|---|
| `word` | per-selection | Select the word at cursor (editor-level, uses editor's word boundary logic) |
| `language-word` | per-selection | Select the word at cursor using the language server's word boundary (respects language-specific identifiers) |
| `page` | per-selection | Move by a percentage of the visible page |
| `next-tab-stop` | per-selection | Jump to next snippet tab stop |
| `prev-tab-stop` | per-selection | Jump to previous snippet tab stop |
| `context-lines` | per-selection | Select context/fold lines. Optional argument filters by kind name. |

## Keybinding examples

### Simple cursor movement: `h` / `l`

```json
"<?-count>h": ["(count* <#move.count>) (column -1)"],
"<?-count>l": ["(count* <#move.count>) (column 1)"],
```

`<?-count>` means an optional count prefix (like `3h`). `<#move.count>` inserts the parsed count. The move multiplies the count, then moves by that many columns.

### Line start: `0`

```json
"0": ["(line) (start)"],
```

Selects the entire current line, then moves to its start (column 0).

### Go to line: `gg`

```json
"<?-count>gg": ["(let c <#move.count>) (if (eq c 0) (start (file)) (start (line-no-indent (line-num (- c 1)))))"],
```

If no count: go to start of file. With count N: go to the first non-whitespace character of line N.

### End of line: `$`

```json
"<?-count>$": ["(line (or <#move.count> 1)) (end)"],
```

Selects `count` lines starting from current, then moves to the end.

### Find character: `f`

```json
"<?-count>f<CHAR>": ["(move-to <move.CHAR>)"],
```

Moves the cursor to the next occurrence of the typed character.

### Till character: `t`

```json
"<?-count>t<CHAR>": ["(column) (move-to <move.CHAR>) (column -1)"],
```

Like `f` but stops one column before the target. It moves to the character, then backs up one column.

### Select inside braces: `i{`

```json
"i{": ["(surround \"{\" \"}\" true)"],
```

Selects the content inside matching `{}` braces. The `true` means "inside only" (excluding the braces themselves).

### Delete with a move: `dw`

```json
"<?-count>d<move>": ["vim.delete-move <move> <#count>"],
```

The `d` operator takes the next move as input. `dw` deletes from cursor to end of word. The move expression is passed to `vim.delete-move` which applies it and deletes the resulting selection.

### VS Code-style extending selection

```json
"<CS-LEFT>": ["move", "(word-line-back) (join orig-start curr-start)"],
```

Moves backward by word, then constructs a new selection: start stays at the original position, end moves to the current cursor. This creates an extending selection.

### VS Code-style cut line: `Ctrl+X`

```json
"<C-x>": ["all",
  [".delete-move", "(line) (column) (join last-start curr-end)", false],
  [".move", "(line) (start) (column target-column)", false, {"wrap": false}]
],
```

Two chained operations: first delete the line, then move to line start preserving the target column.

## Count and repeat

Many vim-style keybindings accept a numeric prefix to repeat an action (e.g., `3w` to move three words). The keybinding system handles this in two parts: parsing the count from the key sequence, then injecting it into the move expression.

### Keybinding pattern syntax

In `keybindings.json`, the count is matched using a pattern like `<?-count>` in the key name. The `?` makes the count optional. For example:

```json
"<?-count>h": ["(count* <#move.count>) (column -1)"],
"<?-count>gg": ["(let c <#move.count>) (if (eq c 0) (start (file)) (start (line-no-indent (line-num (- c 1)))))"],
```

The `#count` pattern is defined at the top level of the keybindings and matches one or more digits:

```json
"#count": {
    "<-1-9><o-0-9>": [""],
},
```

This matches a digit 1-9 optionally followed by more digits 0-9.

### Substitution tokens

The parsed count is injected into the move expression using substitution tokens. The prefix after `#` must match the keybinding namespace:

| Token | Context |
|---|---|
| `<#move.count>` | In `vim#move` keybindings |
| `<#text_object.count>` | In `vim#text_object` keybindings |
| `<#count>` | In generic contexts |

For example, `3h` with the binding `"<?-count>h": ["(count* <#move.count>) (column -1)"]` produces the evaluated expression `(count* 3) (column -1)`.

### How moves use the count

When a move is evaluated, the count is available as the `count` environment variable. Most moves use it automatically -- for example, `column` moves by `count` columns, and `line-up` moves by `count` lines. By default `getCount` returns **1** when no count was entered (count is 0 or nil), so every move runs at least once.

There are several ways to use count in move expressions:

**Multiply the count** with `(count* N)`:
```lisp
(count* <#move.count>) (column -1)    ;; 3h -> count becomes 3, move left 3 columns
```

**Set the count** with `(count= N)`. This directly replaces the count value:
```lisp
(count= 5) (column -1)                ;; always move left exactly 5 columns
```

**Bind the count for branching** with `(let c <#move.count>)`. This gives you the raw parsed value (0 if no count was entered), which is useful for conditional logic:
```lisp
(let c <#move.count>) (if (eq c 0) (start (file)) (start (line-no-indent (line-num (- c 1)))))
```
This is the `gg` binding: with no count, go to start of file; with count N, go to line N.

**Use the count as a move argument**. Some moves accept the count directly as a parameter (e.g., `line` takes how many lines to select):
```lisp
(line (or <#move.count> 1)) (end)     ;; $: select count lines, go to end
```

**Pass count to commands** outside the move DSL. Operator bindings like `d`, `y`, `c` pass the count to their handler command:
```json
"<?-count>d<move>": ["vim.delete-move <move> <#count>"],
"<?-count>y<move>": ["vim.yank-move <move> <#count>"],
"<?-count>c<move>": ["vim.change-move <move> <#count>"],
```

### Operator count and motion count

Vim allows a count on both the operator and the motion: `3d4w` deletes 12 words (3 x 4). In the keybinding system, these are two separate counts that get combined:

1. **Operator count** (`<#count>`) -- the count before the operator key (`3` in `3d4w`). This is passed to the handler command as a separate argument.
2. **Motion count** (`<#move.count>`) -- the count before the motion key (`4` in `4w`). This is substituted into the move expression via `(count* <#move.count>)`.

For `3d4w`:
- The binding `"<?-count>d<move>": ["vim.delete-move <move> <#count>"]` captures `count=3` and substitutes `<move>` with the full move expression for `4w`.
- The move binding `"<?-count>w": ["(count* <#move.count>) (vim.word) (inclusive)"]` produces `(count* 4) (vim.word) (inclusive)`.
- The resulting command is `vim.delete-move (count* 4) (vim.word) (inclusive) 3`.

The handler then applies the motion with `count=4` (from `(count* 4)` setting the environment variable), and repeats the whole operation `3` times (the operator count). The counts multiply: 4 words per repetition x 3 repetitions = 12 words deleted.

The multiplication happens at two levels:

```
3 d 4 w
| | | |
| | | └── motion: vim.word (selects one word by default)
| | └──── motion count: (count* 4) multiplies the base count 3 by 4 to give 12
| └────── operator: vim.delete-move
└──────── operator count: gets passed as the base value for count into the move, then gets multiplied by 4
```

## Environment variables

When a move is evaluated, these environment variables are available:

| Variable | Description |
|---|---|
| `count` | The current repeat count (from e.g. `3w`). Defaults to 1 if no count given. See [Count and repeat](#count-and-repeat). |
| `target-column` | The remembered column from vertical movement |
| `include-eol` | Whether to include end-of-line positions |
| `wrap` | Whether movement wraps across lines |
| `screen-lines` | Number of visible screen lines |
| `num-lines` | Total number of lines in the document |
| `num-bytes` | Total number of bytes in the document |
