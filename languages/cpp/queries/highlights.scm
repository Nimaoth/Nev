; Keywords
[
  "break" @keyword
  "case" @keyword
  "const" @keyword
  "continue" @keyword
  "default" @keyword
  "do" @keyword
  "else" @keyword
  "enum" @keyword
  "extern" @keyword
  "for" @keyword
  "if" @keyword
  "inline" @keyword
  "return" @keyword
  "sizeof" @keyword
  "static" @keyword
  "struct" @keyword
  "typedef" @keyword
  "union" @keyword
  "volatile" @keyword
  "while" @keyword

  "#define"
  "#elif"
  "#else"
  "#endif"
  "#if"
  "#ifdef"
  "#ifndef"
  "#include"
  "catch"
  "class"
  "co_await"
  "co_return"
  "co_yield"
  "constexpr"
  "constinit"
  "consteval"
  "delete"
  "explicit"
  "final"
  "friend"
  "mutable"
  "namespace"
  "noexcept"
  "new"
  "override"
  "private"
  "protected"
  "public"
  "template"
  "throw"
  "try"
  "typename"
  "using"
  "concept"
  "requires"
  (virtual)
  (preproc_directive)
] @keyword

[
  "--"
  "-"
  "-="
  "->"
  "="
  "!="
  "*"
  "&"
  "&&"
  "+"
  "++"
  "+="
  "<"
  "=="
  ">"
  "||"
] @keyword.operator

[
  "."
  ";"
  ":"
  ","
  "::"
] @punctuation.delimiter

[
  "("
  ")"
  "["
  "]"
  "{"
  "}"
] @punctuation.bracket

; Strings

(raw_string_literal) @string
(string_literal) @string
(system_lib_string) @string


(identifier) @variable
(field_identifier) @variable.member

(field_expression
    argument: (identifier) @variable.member)

; Functions

(call_expression
  function: (qualified_identifier
    name: (identifier) @function))

(template_function
  name: (identifier) @function)

(template_method
  name: (field_identifier) @function)

(template_function
  name: (identifier) @function)

(function_declarator
  declarator: (qualified_identifier
    name: (identifier) @function))

(function_declarator
  declarator: (field_identifier) @function)

; Types

((namespace_identifier) @type
 (#match? @type "^[A-Z]"))

(auto) @type

; Constants

(this) @variable.builtin
(null "nullptr" @constant)

(number_literal) @number
(char_literal) @constant.numeric

(call_expression
  function: (identifier) @function.special
  (#match? @function.special "^[A-Z][A-Z\\d_]*$"))

(call_expression
  function: (identifier) @function.call)
(call_expression
  function: (field_expression
    field: (field_identifier) @function.call))
(call_expression
  function: (template_function
    name: (identifier) @function.call))
(function_declarator
  declarator: (identifier) @function)
(preproc_function_def
  name: (identifier) @function.special)
(preproc_ifdef
  name: (identifier) @type)
(preproc_def
  name: (identifier) @type)

(qualified_identifier
    scope: (namespace_identifier) @type)

(field_declaration
  declarator: (function_declarator
    declarator: (field_identifier) @variable.function))

(statement_identifier) @label
(type_identifier) @type
(primitive_type) @type
(sized_type_specifier) @type

((identifier) @constant
 (#match? @constant "^[A-Z][A-Z\\d_]*$"))

(comment) @comment
