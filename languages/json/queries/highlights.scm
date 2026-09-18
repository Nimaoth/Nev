(string) @string

(pair
  key: (_) @string.special.key)

(number) @number

[
  (null)
  (true)
  (false)
] @constant.builtin

(escape_sequence) @escape

(comment) @comment

(identifier) @variable.member
(quote marker: _ @keyword)
(unquote marker: _ @number)
(quasiquote marker: _ @string)
(unquote_splicing marker: _ @type)
; (unquote) @keyword
; (quasyquote) @keyword
; (unquote-splicing) @keyword

((identifier) @number
 (#match? @number "^[+-][0-9]+[u]$"))

((identifier) @keyword
 (#match? @keyword "^\\.$"))

(list . (identifier) @keyword)
