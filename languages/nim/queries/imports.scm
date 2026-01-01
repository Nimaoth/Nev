
(import_statement (identifier) @import)
(import_statement (expression_list (identifier) @import))
(import_statement (expression_list (infix_expression right: (identifier) @import)))
(import_statement (expression_list (infix_expression right: (array_construction (identifier) @import))))

(export_statement (expression_list (identifier) @export))
