## Key

:white-white_check_mark-mark: - command done

:white_check_mark: :star: - command done with specific customization

:warning: - some variations of the command are not supported

:running: - work in progress

:arrow_down: - command is low priority; open an issue (or thumbs up the relevant issue) if you want to see it sooner

:x: - command impossible

:1234: - command accepts numeric prefix

## Left-right motions

| Status                    | Command        | Description                                                                    | Note      |
| ------------------------- | -------------- | ------------------------------------------------------------------------------ | --------- |
| :white_check_mark:        | :1234: h       | left (also: BS, or Left key)                                                   |           |
| :white_check_mark:        | :1234: l       | right (also: Space or Right key)                                               |           |
| :white_check_mark:        | 0              | to first character in the line (also: Home key)                                |           |
| :white_check_mark:        | ^              | to first non-blank character in the line                                       |           |
| :white_check_mark:        | :1234: \$      | to the last character in the line (N-1 lines lower) (also: End key)            |           |
| :white_check_mark: :star: | g0             | to first character in screen line (differs from "0" when lines wrap)           | Same as 0 |
| :white_check_mark: :star: | g^             | to first non-blank character in screen line (differs from "^" when lines wrap) | Same as ^ |
| :white_check_mark: :star: | :1234: g\$     | to last character in screen line (differs from "\$" when lines wrap)           | Same as $ |
| :white_check_mark:        | gm             | to middle of the screen line                                                   |           |
| :white_check_mark:        | :1234: \|      | to column N (default: 1)                                                       |           |
| :running:                 | :1234: f{char} | to the Nth occurrence of {char} to the right                                   |           |
| :running:                 | :1234: F{char} | to the Nth occurrence of {char} to the left                                    |           |
| :running:                 | :1234: t{char} | till before the Nth occurrence of {char} to the right                          |           |
| :running:                 | :1234: T{char} | till before the Nth occurrence of {char} to the left                           |           |
| :running:                 | :1234: ;       | repeat the last "f", "F", "t", or "T" N times                                  |           |
| :running:                 | :1234: ,       | repeat the last "f", "F", "t", or "T" N times in opposite direction            |           |

## Up-down motions

| Status                    | Command   | Description                                                                               | Note      |
| ------------------------- | --------- | ----------------------------------------------------------------------------------------- | --------- |
| :white_check_mark:        | :1234: k  | up N lines (also: CTRL-P and Up)                                                          |           |
| :white_check_mark:        | :1234: j  | down N lines (also: CTRL-J, CTRL-N, NL, and Down)                                         |           |
| :white_check_mark:        | :1234: -  | up N lines, on the first non-blank character                                              |           |
| :white_check_mark:        | :1234: +  | down N lines, on the first non-blank character (also: CTRL-M and CR)                      |           |
| :white_check_mark:        | :1234: \_ | down N-1 lines, on the first non-blank character                                          |           |
| :white_check_mark:        | :1234: G  | goto line N (default: last line), on the first non-blank character                        |           |
| :white_check_mark:        | :1234: gg | goto line N (default: first line), on the first non-blank character                       |           |
| :white_check_mark:        | :1234: %  | goto line N percentage down in the file; N must be given, otherwise it is the `%` command |           |
| :white_check_mark: :star: | :1234: gk | up N screen lines (differs from "k" when line wraps)                                      | Same as k |
| :white_check_mark: :star: | :1234: gj | down N screen lines (differs from "j" when line wraps)                                    | Same as j |

## Text object motions

| Status       | Command    | Description                                                 |
| ------------ | ---------- | ----------------------------------------------------------- |
| :running:    | :1234: w   | N words forward                                             |
| :running:    | :1234: W   | N blank-separated WORDs forward                             |
| :running:    | :1234: e   | N words forward to the end of the Nth word                  |
| :running:    | :1234: E   | N words forward to the end of the Nth blank-separated WORD  |
| :running:    | :1234: b   | N words backward                                            |
| :running:    | :1234: B   | N blank-separated WORDs backward                            |
| :running:    | :1234: ge  | N words backward to the end of the Nth word                 |
| :running:    | :1234: gE  | N words backward to the end of the Nth blank-separated WORD |
| :running:    | :1234: )   | N sentences forward                                         |
| :running:    | :1234: (   | N sentences backward                                        |
| :running:    | :1234: }   | N paragraphs forward                                        |
| :running:    | :1234: {   | N paragraphs backward                                       |
| :running:    | :1234: ]]  | N sections forward, at start of section                     |
| :running:    | :1234: [[  | N sections backward, at start of section                    |
| :running:    | :1234: ][  | N sections forward, at end of section                       |
| :running:    | :1234: []  | N sections backward, at end of section                      |
| :running:    | :1234: [(  | N times back to unclosed '('                                |
| :running:    | :1234: [{  | N times back to unclosed '{'                                |
| :arrow_down: | :1234: [m  | N times back to start of method (for Java)                  |
| :arrow_down: | :1234: [M  | N times back to end of method (for Java)                    |
| :running:    | :1234: ])  | N times forward to unclosed ')'                             |
| :running:    | :1234: ]}  | N times forward to unclosed '}'                             |
| :arrow_down: | :1234: ]m  | N times forward to start of method (for Java)               |
| :arrow_down: | :1234: ]M  | N times forward to end of method (for Java)                 |
| :arrow_down: | :1234: [#  | N times back to unclosed "#if" or "#else"                   |
| :arrow_down: | :1234: ]#  | N times forward to unclosed "#else" or "#endif"             |
| :arrow_down: | :1234: [\* | N times back to start of a C comment "/\*"                  |
| :arrow_down: | :1234: ]\* | N times forward to end of a C comment "\*/"                 |

## Pattern searches

| Status                    | Command                            | Description                                            | Note |
| ------------------------- | ---------------------------------- | ------------------------------------------------------ | ---- |
| :running:          :star: | :1234: `/{pattern}[/[offset]]<CR>` | search forward for the Nth occurrence of {pattern}     |      |
| :running:          :star: | :1234: `?{pattern}[?[offset]]<CR>` | search backward for the Nth occurrence of {pattern}    |      |
| :running:                 | :1234: `/<CR>`                     | repeat last search, in the forward direction           |      |
| :running:                 | :1234: `?<CR>`                     | repeat last search, in the backward direction          |      |
| :running:                 | :1234: n                           | repeat last search                                     |      |
| :running:                 | :1234: N                           | repeat last search, in opposite direction              |      |
| :running:                 | :1234: \*                          | search forward for the identifier under the cursor     |      |
| :running:                 | :1234: #                           | search backward for the identifier under the cursor    |      |
| :running:                 | :1234: g\*                         | like "\*", but also find partial matches               |      |
| :running:                 | :1234: g#                          | like "#", but also find partial matches                |      |
| :running:                 | gd                                 | goto local declaration of identifier under the cursor  |      |
| :arrow_down:              | gD                                 | goto global declaration of identifier under the cursor |      |

## Marks and motions

| Status       | Command             | Description                                            |
| ------------ | ------------------- | ------------------------------------------------------ |
| :running:    | m{a-zA-Z}           | mark current position with mark {a-zA-Z}               |
| :running:    | \`{a-z}             | go to mark {a-z} within current file                   |
| :running:    | \`{A-Z}             | go to mark {A-Z} in any file                           |
| :running:    | \`{0-9}             | go to the position where Vim was previously exited     |
| :running:    | \`                  | go to the position before the last jump                |
| :arrow_down: | \`"                 | go to the position when last editing this file         |
| :running:    | \`[                 | go to the start of the previously operated or put text |
| :running:    | '[                  | go to the start of the previously operated or put text |
| :running:    | \`]                 | go to the end of the previously operated or put text   |
| :running:    | ']                  | go to the end of the previously operated or put text   |
| :arrow_down: | \`<                 | go to the start of the (previous) Visual area          |
| :arrow_down: | \`>                 | go to the end of the (previous) Visual area            |
| :running:    | \`.                 | go to the position of the last change in this file     |
| :running:    | '.                  | go to the position of the last change in this file     |
| :arrow_down: | '{a-zA-Z0-9[]'"<>.} | same as `, but on the first non-blank in the line      |
| :arrow_down: | :marks              | print the active marks                                 |
| :running:    | :1234: CTRL-O       | go to Nth older position in jump list                  |
| :running:    | :1234: CTRL-I       | go to Nth newer position in jump list                  |
| :arrow_down: | :ju[mps]            | print the jump list                                    |

## Various motions

| Status       | Command             | Description                                                                                        |
| ------------ | ------------------- | -------------------------------------------------------------------------------------------------- |
| :running:    | %                   | find the next brace, bracket, comment, or "#if"/ "#else"/"#endif" in this line and go to its match |
| :running:    | :1234: H            | go to the Nth line in the window, on the first non-blank                                           |
| :running:    | M                   | go to the middle line in the window, on the first non-blank                                        |
| :running:    | :1234: L            | go to the Nth line from the bottom, on the first non-blank                                         |
| :arrow_down: | :1234: go           | go to Nth byte in the buffer                                                                       |
| :arrow_down: | :[range]go[to][off] | go to [off] byte in the buffer                                                                     |

## Using tags

| Status       | Command                | Description                                                           |
| ------------ | ---------------------- | --------------------------------------------------------------------- |
| :arrow_down: | :ta[g][!] {tag}        | jump to tag {tag}                                                     |
| :arrow_down: | :[count]ta[g][!]       | jump to [count]'th newer tag in tag list                              |
| :arrow_down: | CTRL-]                 | jump to the tag under cursor, unless changes have been made           |
| :arrow_down: | :ts[elect][!] [tag]    | list matching tags and select one to jump to                          |
| :arrow_down: | :tj[ump][!] [tag]      | jump to tag [tag] or select from list when there are multiple matches |
| :arrow_down: | :lt[ag][!] [tag]       | jump to tag [tag] and add matching tags to the location list          |
| :arrow_down: | :tagsa                 | print tag list                                                        |
| :arrow_down: | :1234: CTRL-T          | jump back from Nth older tag in tag list                              |
| :arrow_down: | :[count]po[p][!]       | jump back from [count]'th older tag in tag list                       |
| :arrow_down: | :[count]tn[ext][!]     | jump to [count]'th next matching tag                                  |
| :arrow_down: | :[count]tp[revious][!] | jump to [count]'th previous matching tag                              |
| :arrow_down: | :[count]tr[ewind][!]   | jump to [count]'th matching tag                                       |
| :arrow_down: | :tl[ast][!]            | jump to last matching tag                                             |
| :arrow_down: | :pt[ag] {tag}          | open a preview window to show tag {tag}                               |
| :arrow_down: | CTRL-W }               | like CTRL-] but show tag in preview window                            |
| :arrow_down: | :pts[elect]            | like ":tselect" but show tag in preview window                        |
| :arrow_down: | :ptj[ump]              | like ":tjump" but show tag in preview window                          |
| :arrow_down: | :pc[lose]              | close tag preview window                                              |
| :arrow_down: | CTRL-W z               | close tag preview window`                                             |

## Scrolling

| Status             | Command       | Description                                    |
| ------------------ | ------------- | ---------------------------------------------- |
| :white_check_mark: | :1234: CTRL-E | window N lines downwards (default: 1)          |
| :white_check_mark: | :1234: CTRL-D | window N lines Downwards (default: 1/2 window) |
| :white_check_mark: | :1234: CTRL-F | window N pages Forwards (downwards)            |
| :white_check_mark: | :1234: CTRL-Y | window N lines upwards (default: 1)            |
| :white_check_mark: | :1234: CTRL-U | window N lines Upwards (default: 1/2 window)   |
| :white_check_mark: | :1234: CTRL-B | window N pages Backwards (upwards)             |
| :white_check_mark: | z CR or zt    | redraw, current line at top of window          |
| :white_check_mark: | z. or zz      | redraw, current line at center of window       |
| :white_check_mark: | z- or zb      | redraw, current line at bottom of window       |

These only work when 'wrap' is off:

| Status                    | Command   | Description                                   | Note |
| ------------------------- | --------- | --------------------------------------------- | ---- |
| :running:          :star: | :1234: zh | scroll screen N characters to the right       |      |
| :running:          :star: | :1234: zl | scroll screen N characters to the left        |      |
| :running:          :star: | :1234: zH | scroll screen half a screenwidth to the right |      |
| :running:          :star: | :1234: zL | scroll screen half a screenwidth to the left  |      |

## Inserting text

| Status             | Command | Description                                                  |
| ------------------ | ------- | ------------------------------------------------------------ |
| :white_check_mark: | a       | append text after the cursor                                 |
| :white_check_mark: | A       | append text at the end of the line                           |
| :white_check_mark: | i       | switch to insert mode                                        |
| :white_check_mark: | I       | switch to insert mode before the first non-blank in the line |
| :white_check_mark: | gI      | insert text in column 1                                      |
| :running:          | gi      | insert at the end of the last change                         |
| :white_check_mark: | o       | open a new line below the current line, append text          |
| :white_check_mark: | O       | open a new line above the current line, append text          |

## Insert mode keys

leaving Insert mode:

| Status             | Command          | Description                                 |
| ------------------ | ---------------- | ------------------------------------------- |
| :white_check_mark: | Esc              | end Insert mode, back to Normal mode        |
| :white_check_mark: | CTRL-C           | like Esc, but do not use an abbreviation    |
| :running:          | CTRL-O {command} | execute {command} and return to Insert mode |

moving around:

| Status             | Command          | Description                             |
| ------------------ | ---------------- | --------------------------------------- |
| :white_check_mark: | cursor keys      | move cursor left/right/up/down          |
| :running:          | shift-left/right | one word left/right                     |
| :running:          | shift-up/down    | one screenful backward/forward          |
| :white_check_mark: | End              | cursor after last character in the line |
| :white_check_mark: | Home             | cursor to first character in the line   |

## Special keys in Insert mode

| Status             | Command                      | Description                                                        | Note |
| ------------------ | ---------------------------- | ------------------------------------------------------------------ | ---- |
| :arrow_down:       | CTRL-V {char}..              | insert character literally, or enter decimal byte value            |      |
| :white_check_mark: | NL or CR or CTRL-M or CTRL-J | begin new line                                                     |      |
| :arrow_down:       | CTRL-E                       | insert the character from below the cursor                         |      |
| :arrow_down:       | CTRL-Y                       | insert the character from above the cursor                         |      |
| :arrow_down:       | CTRL-A                       | insert previously inserted text                                    |      |
| :arrow_down:       | CTRL-@                       | insert previously inserted text and stop Insert mode               |      |
| :white_check_mark: | CTRL-R {0-9a-z%#:.-="}       | insert the contents of a register                                  |      |
| :arrow_down:       | CTRL-N                       | insert next match of identifier before the cursor                  |      |
| :arrow_down:       | CTRL-P                       | insert previous match of identifier before the cursor              |      |
| :arrow_down:       | CTRL-X ...                   | complete the word before the cursor in various ways                |      |
| :white_check_mark: | BS or CTRL-H                 | delete the character before the cursor                             |      |
| :white_check_mark: | Del                          | delete the character under the cursor                              |      |
| :white_check_mark: | CTRL-W                       | delete word before the cursor                                      |      |
| :white_check_mark: | CTRL-U                       | delete all entered characters in the current line                  |      |
| :white_check_mark: | CTRL-T                       | insert one shiftwidth of indent in front of the current line       |      |
| :white_check_mark: | CTRL-D                       | delete one shiftwidth of indent in front of the current line       |      |
| :arrow_down:       | 0 CTRL-D                     | delete all indent in the current line                              |      |
| :arrow_down:       | ^ CTRL-D                     | delete all indent in the current line, restore indent in next line |      |

## Digraphs

| Status       | Command                                 | Description                   |
| ------------ | --------------------------------------- | ----------------------------- |
| :running:    | :dig[raphs]                             | show current list of digraphs |
| :arrow_down: | :dig[raphs] {char1}{char2} {number} ... | add digraph(s) to the list    |

## Special inserts

| Status    | Command       | Description                                              |
| --------- | ------------- | -------------------------------------------------------- |
| :running: | :r [file]     | insert the contents of [file] below the cursor           |
| :running: | :r! {command} | insert the standard output of {command} below the cursor |

## Deleting text

| Status    | Command          | Description                                        |
| --------- | ---------------- | -------------------------------------------------- |
| :running: | :1234: x         | delete N characters under and after the cursor     |
| :running: | :1234: Del       | delete N characters under and after the cursor     |
| :running: | :1234: X         | delete N characters before the cursor              |
| :running: | :1234: d{motion} | delete the text that is moved over with {motion}   |
| :running: | {visual}d        | delete the highlighted text                        |
| :running: | :1234: dd        | delete N lines                                     |
| :running: | :1234: D         | delete to the end of the line (and N-1 more lines) |
| :running: | :1234: J         | join N-1 lines (delete EOLs)                       |
| :running: | {visual}J        | join the highlighted lines                         |
| :running: | :1234: gJ        | like "J", but without inserting spaces             |
| :running: | {visual}gJ       | like "{visual}J", but without inserting spaces     |
| :running: | :[range]d [x]    | delete [range] lines [into register x]             |

## Copying and moving text

| Status    | Command          | Description                                            |
| --------- | ---------------- | ------------------------------------------------------ |
| :running: | "{char}          | use register {char} for the next delete, yank, or put  |
| :running: | "\*              | use register `*` to access system clipboard            |
| :running: | :reg             | show the contents of all registers                     |
| :running: | :reg {arg}       | show the contents of registers mentioned in {arg}      |
| :running: | :1234: y{motion} | yank the text moved over with {motion} into a register |
| :running: | {visual}y        | yank the highlighted text into a register              |
| :running: | :1234: yy        | yank N lines into a register                           |
| :running: | :1234: Y         | yank N lines into a register                           |
| :running: | :1234: p         | put a register after the cursor position (N times)     |
| :running: | :1234: P         | put a register before the cursor position (N times)    |
| :running: | :1234: ]p        | like p, but adjust indent to current line              |
| :running: | :1234: [p        | like P, but adjust indent to current line              |
| :running: | :1234: gp        | like p, but leave cursor after the new text            |
| :running: | :1234: gP        | like P, but leave cursor after the new text            |

## Changing text

| Status                    | Command         | Description                                                                                       | Note |
| ------------------------- | --------------- | ------------------------------------------------------------------------------------------------- | ---- |
| :running:                 | :1234: r{char}  | replace N characters with {char}                                                                  |      |
| :arrow_down:              | :1234: gr{char} | replace N characters without affecting layout                                                     |      |
| :running:          :star: | :1234: R        | enter Replace mode (repeat the entered text N times)                                              |      |
| :arrow_down:              | :1234: gR       | enter virtual Replace mode: Like Replace mode but without affecting layout                        |      |
| :running:                 | {visual}r{char} | in Visual block, visual, or visual line modes: Replace each char of the selected text with {char} |      |

(change = delete text and enter Insert mode)

| Status       | Command                 | Description                                                                                     |
| ------------ | ----------------------- | ----------------------------------------------------------------------------------------------- |
| :running:    | :1234: c{motion}        | change the text that is moved over with {motion}                                                |
| :running:    | {visual}c               | change the highlighted text                                                                     |
| :running:    | :1234: cc               | change N lines                                                                                  |
| :running:    | :1234: S                | change N lines                                                                                  |
| :running:    | :1234: C                | change to the end of the line (and N-1 more lines)                                              |
| :running:    | :1234: s                | change N characters                                                                             |
| :running:    | {visual}c               | in Visual block mode: Change each of the selected lines with the entered text                   |
| :running:    | {visual}C               | in Visual block mode: Change each of the selected lines until end-of-line with the entered text |
| :running:    | {visual}~               | switch case for highlighted text                                                                |
| :running:    | {visual}u               | make highlighted text lowercase                                                                 |
| :running:    | {visual}U               | make highlighted text uppercase                                                                 |
| :running:    | g~{motion}              | switch case for the text that is moved over with {motion}                                       |
| :running:    | gu{motion}              | make the text that is moved over with {motion} lowercase                                        |
| :running:    | gU{motion}              | make the text that is moved over with {motion} uppercase                                        |
| :running:    | {visual}g?              | perform rot13 encoding on highlighted text                                                      |
| :running:    | g?{motion}              | perform rot13 encoding on the text that is moved over with {motion}                             |
| :running:    | :1234: CTRL-A           | add N to the number at or after the cursor                                                      |
| :running:    | :1234: CTRL-X           | subtract N from the number at or after the cursor                                               |
| :running:    | :1234: <{motion}        | move the lines that are moved over with {motion} one shiftwidth left                            |
| :running:    | :1234: <<               | move N lines one shiftwidth left                                                                |
| :running:    | :1234: >{motion}        | move the lines that are moved over with {motion} one shiftwidth right                           |
| :running:    | :1234: >>               | move N lines one shiftwidth right                                                               |
| :running:    | :1234: gq{motion}       | format the lines that are moved over with {motion} to 'textwidth' length                        |
| :arrow_down: | :[range]ce[nter][width] | center the lines in [range]                                                                     |
| :arrow_down: | :[range]le[ft][indent]  | left-align the lines in [range] (with [indent])                                                 |
| :arrow_down: | :[range]ri[ght][width]  | right-align the lines in [range]                                                                |

## Complex changes

| Status                              | Command                                        | Description                                                                                                                           | Note |
| ----------------------------------- | ---------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- | ---- |
| :arrow_down:                        | :1234: `!{motion}{command}<CR>`                | filter the lines that are moved over through {command}                                                                                |      |
| :arrow_down:                        | :1234: `!!{command}<CR>`                       | filter N lines through {command}                                                                                                      |      |
| :arrow_down:                        | `{visual}!{command}<CR>`                       | filter the highlighted lines through {command}                                                                                        |      |
| :arrow_down:                        | `:[range]! {command}<CR>`                      | filter [range] lines through {command}                                                                                                |      |
| :running:                           | :1234: ={motion}                               | filter the lines that are moved over through 'equalprg'                                                                               |      |
| :running:                           | :1234: ==                                      | filter N lines through 'equalprg'                                                                                                     |      |
| :running:                           | {visual}=                                      | filter the highlighted lines through 'equalprg'                                                                                       |      |
| :running:          :star: :running: | :[range]s[ubstitute]/{pattern}/{string}/[g][c] | substitute {pattern} by {string} in [range] lines; with [g], replace all occurrences of {pattern}; with [c], confirm each replacement |      |
| :arrow_down:                        | :[range]s[ubstitute][g][c]                     | repeat previous ":s" with new range and options                                                                                       |      |
| :arrow_down:                        | &                                              | Repeat previous ":s" on current line without options                                                                                  |      |
| :arrow_down:                        | :[range]ret[ab][!] [tabstop]                   | set 'tabstop' to new value and adjust white space accordingly                                                                         |      |

## Visual mode

| Status    | Command | Description                                         |
| --------- | ------- | --------------------------------------------------- |
| :running: | v       | start highlighting characters or stop highlighting  |
| :running: | V       | start highlighting linewise or stop highlighting    |
| :running: | CTRL-V  | start highlighting blockwise or stop highlighting   |
| :running: | o       | exchange cursor position with start of highlighting |
| :running: | gv      | start highlighting on previous visual area          |

## Text objects (only in Visual mode or after an operator)

| Status    | Command           | Description                                                                                  |
| --------- | ----------------- | -------------------------------------------------------------------------------------------- |
| :running: | :1234: aw         | Select "a word"                                                                              |
| :running: | :1234: iw         | Select "inner word"                                                                          |
| :running: | :1234: aW         | Select "a WORD"                                                                              |
| :running: | :1234: iW         | Select "inner WORD"                                                                          |
| :running: | :1234: as         | Select "a sentence"                                                                          |
| :running: | :1234: is         | Select "inner sentence"                                                                      |
| :running: | :1234: ap         | Select "a paragraph"                                                                         |
| :running: | :1234: ip         | Select "inner paragraph"                                                                     |
| :running: | :1234: a], a[     | select '[' ']' blocks                                                                        |
| :running: | :1234: i], i[     | select inner '[' ']' blocks                                                                  |
| :running: | :1234: ab, a(, a) | Select "a block" (from "[(" to "])")                                                         |
| :running: | :1234: ib, i), i( | Select "inner block" (from "[(" to "])")                                                     |
| :running: | :1234: a>, a<     | Select "a &lt;&gt; block"                                                                    |
| :running: | :1234: i>, i<     | Select "inner <> block"                                                                      |
| :running: | :1234: aB, a{, a} | Select "a Block" (from "[{" to "]}")                                                         |
| :running: | :1234: iB, i{, i} | Select "inner Block" (from "[{" to "]}")                                                     |
| :running: | :1234: at         | Select "a tag block" (from &lt;aaa&gt; to &lt;/aaa&gt;)                                      |
| :running: | :1234: it         | Select "inner tag block" (from &lt;aaa&gt; to &lt;/aaa&gt;)                                  |
| :running: | :1234: a'         | Select "a single quoted string"                                                              |
| :running: | :1234: i'         | Select "inner single quoted string"                                                          |
| :running: | :1234: a"         | Select "a double quoted string"                                                              |
| :running: | :1234: i"         | Select "inner double quoted string"                                                          |
| :running: | :1234: a\`        | Select "a backward quoted string"                                                            |
| :running: | :1234: i\`        | Select "inner backward quoted string"                                                        |
| :running: | :1234: ia         | Select "inner argument" from the [targets.vim plugin](https://github.com/wellle/targets.vim) |
| :running: | :1234: aa         | Select "an argument" from the [targets.vim plugin](https://github.com/wellle/targets.vim)    |

## Repeating commands

| Status                    | Command                           | Description                                                                                        | Note |
| ------------------------- | --------------------------------- | -------------------------------------------------------------------------------------------------- | ---- |
| :running:          :star: | :1234: .                          | repeat last change (with count replaced with N)                                                    |      |
| :running:                 | q{a-z}                            | record typed characters into register {a-z}                                                        |      |
| :arrow_down:              | q{A-Z}                            | record typed characters, appended to register {a-z}                                                |      |
| :running:                 | q                                 | stop recording                                                                                     |      |
| :running:                 | :1234: @{a-z}                     | execute the contents of register {a-z} (N times)                                                   |      |
| :running:                 | :1234: @@                         | repeat previous @{a-z} (N times)                                                                   |      |
| :arrow_down:              | :@{a-z}                           | execute the contents of register {a-z} as an Ex command                                            |      |
| :arrow_down:              | :@@                               | repeat previous :@{a-z}                                                                            |      |
| :arrow_down:              | :[range]g[lobal]/{pattern}/[cmd]  | execute Ex command [cmd](default: ':p') on the lines within [range] where {pattern} matches        |      |
| :arrow_down:              | :[range]g[lobal]!/{pattern}/[cmd] | execute Ex command [cmd](default: ':p') on the lines within [range] where {pattern} does NOT match |      |
| :arrow_down:              | :so[urce] {file}                  | read Ex commands from {file}                                                                       |      |
| :arrow_down:              | :so[urce]! {file}                 | read Vim commands from {file}                                                                      |      |
| :arrow_down:              | :sl[eep][sec]                     | don't do anything for [sec] seconds                                                                |      |
| :arrow_down:              | :1234: gs                         | goto Sleep for N seconds                                                                           |      |

## Undo/Redo commands

| Status    | Command       | Description                | Note                                                       |
| --------- | ------------- | -------------------------- | ---------------------------------------------------------- |
| :running: | :1234: u      | undo last N changes        | Current implementation may not cover every case perfectly. |
| :running: | :1234: CTRL-R | redo last N undone changes | As above.                                                  |
| :running: | U             | restore last changed line  |                                                            |

## External commands

| Status       | Command     | Description                                                                |
| ------------ | ----------- | -------------------------------------------------------------------------- |
| :running:    | :sh[ell]    | start a shell                                                              |
| :running:    | :!{command} | execute {command} with a shell                                             |
| :arrow_down: | K           | lookup keyword under the cursor with 'keywordprg' program (default: "man") |

## Ex ranges

| Status                    | Command       | Description                                                                  | Note |
| ------------------------- | ------------- | ---------------------------------------------------------------------------- | ---- |
| :running:                 | ,             | separates two line numbers                                                   |      |
| :running:          :star: | ;             | idem, set cursor to the first line number before interpreting the second one |      |
| :running:                 | {number}      | an absolute line number                                                      |      |
| :running:                 | .             | the current line                                                             |      |
| :running:                 | \$            | the last line in the file                                                    |      |
| :running:                 | %             | equal to 1,\$ (the entire file)                                              |      |
| :running:                 | \*            | equal to '<,'> (visual area)                                                 |      |
| :running:                 | 't            | position of mark t                                                           |      |
| :arrow_down:              | /{pattern}[/] | the next line where {pattern} matches                                        |      |
| :arrow_down:              | ?{pattern}[?] | the previous line where {pattern} matches                                    |      |
| :running:                 | +[num]        | add [num] to the preceding line number (default: 1)                          |      |
| :running:                 | -[num]        | subtract [num] from the preceding line number (default: 1)                   |      |

## Editing a file

| Status                    | Command        | Description  | Note |
| ------------------------- | -------------- | ------------ | ---- |
| :running:          :star: | :e[dit] {file} | Edit {file}. |      |

## Multi-window commands

| Status                    | Command           | Description                                                             | Note |
| ------------------------- | ----------------- | ----------------------------------------------------------------------- | ---- |
| :running:          :star: | :e[dit] {file}    | Edit {file}.                                                            |      |
| :running:          :star: | &lt;ctrl-w&gt; hl | Switching between windows.                                              |      |
| :running:                 | :sp {file}        | Split current window in two.                                            |      |
| :running:          :star: | :vsp {file}       | Split vertically current window in two.                                 |      |
| :running:                 | &lt;ctrl-w&gt; s  | Split current window in two.                                            |      |
| :running:          :star: | &lt;ctrl-w&gt; v  | Split vertically current window in two.                                 |      |
| :running:          :star: | &lt;ctrl-w&gt; o  | Close other editor groups.                                              |      |
| :running:                 | :new              | Create a new window horizontally and start editing an empty file in it. |      |
| :running:          :star: | :vne[w]           | Create a new window vertically and start editing an empty file in it.   |      |

## Tabs

| Status                    | Command                              | Description                                                                   | Note |
| ------------------------- | ------------------------------------ | ----------------------------------------------------------------------------- | ---- |
| :running:                 | :tabn[ext] :1234:                    | Go to next tab page or tab page {count}. The first tab page has number one.   |      |
| :running:                 | {count}&lt;C-PageDown&gt;, {count}gt | Same as above                                                                 |      |
| :running:                 | :tabp[revious] :1234:                | Go to the previous tab page. Wraps around from the first one to the last one. |      |
| :running:                 | :tabN[ext] :1234:                    | Same as above                                                                 |      |
| :running:                 | {count}&lt;C-PageUp&gt;, {count}gT   | Same as above                                                                 |      |
| :running:                 | :tabfir[st]                          | Go to the first tab page.                                                     |      |
| :running:                 | :tabl[ast]                           | Go to the last tab page.                                                      |      |
| :running:                 | :tabe[dit] {file}                    | Open a new tab page with an empty window, after the current tab page          |      |
| :arrow_down:              | :[count]tabe[dit], :[count]tabnew    | Same as above                                                                 |      |
| :running:                 | :tabnew {file}                       | Open a new tab page with an empty window, after the current tab page          |      |
| :arrow_down:              | :[count]tab {cmd}                    | Execute {cmd} and when it opens a new window open a new tab page instead.     |      |
| :running:          :star: | :tabc[lose][!] :1234:                | Close current tab page or close tab page {count}.                             |      |
| :running:          :star: | :tabo[nly][!]                        | Close all other tab pages.                                                    |      |
| :running:                 | :tabm[ove][n]                        | Move the current tab page to after tab page N.                                |      |
| :arrow_down:              | :tabs                                | List the tab pages and the windows they contain.                              |      |
| :arrow_down:              | :tabd[o] {cmd}                       | Execute {cmd} in each tab page.                                               |      |
