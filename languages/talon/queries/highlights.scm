(word) @keyword
(string_content) @string
["\""] @string
(implicit_string) @constant
(integer) @constant
(float) @constant
(string_escape_sequence) @escape

(action
  action_name: (identifier) @function.call)

(tag_binding) @function.call

(settings_binding) @function.call

(match
  left: (identifier) @type)

(assignment_statement
  left: (identifier) @parameter)

(key_action) @function
(sleep_action) @function

((identifier) @parameter
  (#match? @parameter "^user\.[a-zA-Z0-9_]+$"))
((identifier) @constant
  (#match? @constant "^(true|false)$"))
(identifier) @variable.builtin

(start_anchor) @punctuation.delimiter
(end_anchor) @punctuation.delimiter
(operator) @operator
[ "-" "=" "|" ] @operator
[ "," ":" ] @punctuation.delimiter
[ "(" ")" "[" "]" "<" ">" ] @punctuation.bracket

[
  (comment)
] @comment
