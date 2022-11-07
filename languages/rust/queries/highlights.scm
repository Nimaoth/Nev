; Identifier conventions

; Assume all-caps names are constants
((identifier) @variable.other.constant
 (#match? @variable.other.constant "^[A-Z][A-Z\\d_]+$'"))

; Assume that uppercase names in paths are types
((scoped_identifier
  path: (identifier) @storage.type)
 (#match? @storage.type "^[A-Z]"))
((scoped_identifier
  path: (scoped_identifier
    name: (identifier) @storage.type))
 (#match? @storage.type "^[A-Z]"))
((scoped_type_identifier
  path: (identifier) @storage.type)
 (#match? @storage.type "^[A-Z]"))
((scoped_type_identifier
  path: (scoped_identifier
    name: (identifier) @storage.type))
 (#match? @storage.type "^[A-Z]"))

; Assume other uppercase names are enum constructors
((identifier) @variable.function.constructor
 (#match? @variable.function.constructor "^[A-Z]"))

; Assume all qualified names in struct patterns are enum constructors. (They're
; either that, or struct names; highlighting both as constructors seems to be
; the less glaring choice of error, visually.)
(struct_pattern
  type: (scoped_type_identifier
    name: (type_identifier) @variable.function.constructor))

; Function calls

(call_expression
  function: (identifier) @variable.function)
(call_expression
  function: (field_expression
    field: (field_identifier) @variable.function.constructor))
(call_expression
  function: (scoped_identifier
    "::"
    name: (identifier) @variable.function))

(generic_function
  function: (identifier) @variable.function)
(generic_function
  function: (scoped_identifier
    name: (identifier) @variable.function))
(generic_function
  function: (field_expression
    field: (field_identifier) @variable.function.constructor))

(macro_invocation
  macro: (identifier) @variable.function
  "!" @variable.function)

; Function definitions

(function_item (identifier) @variable.function)
(function_signature_item (identifier) @variable.function)

; Other identifiers

(type_identifier) @storage.type
(primitive_type) @storage.type
(field_identifier) @variable.other.property

(line_comment) @comment
(block_comment) @comment

"(" @punctuation.bracket
")" @punctuation.bracket
"[" @punctuation.bracket
"]" @punctuation.bracket
"{" @punctuation.bracket
"}" @punctuation.bracket

(type_arguments
  "<" @punctuation.bracket
  ">" @punctuation.bracket)
(type_parameters
  "<" @punctuation.bracket
  ">" @punctuation.bracket)

"::" @punctuation.delimiter
":" @punctuation.delimiter
"." @punctuation.delimiter
"," @punctuation.delimiter
";" @punctuation.delimiter

(parameter (identifier) @variable.parameter)

(lifetime (identifier) @label)

"as" @keyword
"async" @keyword
"await" @keyword
"break" @keyword
"const" @keyword
"continue" @keyword
"default" @keyword
"dyn" @keyword
"else" @keyword
"enum" @keyword
"extern" @keyword
"fn" @keyword
"for" @keyword
"if" @keyword
"impl" @keyword
"in" @keyword
"let" @keyword
"loop" @keyword
"macro_rules!" @keyword
"match" @keyword
"mod" @keyword
"move" @keyword
"pub" @keyword
"ref" @keyword
"return" @keyword
"static" @keyword
"struct" @keyword
"trait" @keyword
"type" @keyword
"union" @keyword
"unsafe" @keyword
"use" @keyword
"where" @keyword
"while" @keyword
(crate) @keyword
(mutable_specifier) @keyword
(use_list (self) @keyword)
(scoped_use_list (self) @keyword)
(scoped_identifier (self) @keyword)
(super) @keyword

(self) @variable.builtin

(char_literal) @string
(string_literal) @string
(raw_string_literal) @string

(boolean_literal) @variable.other.constant
(integer_literal) @constant.numeric
(float_literal) @constant.numeric

(escape_sequence) @escape

(attribute_item) @attribute
(inner_attribute_item) @attribute

"*" @operator
"&" @operator
"'" @operator