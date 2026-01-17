import "../modules/test_module2.nim"
import "../modules/language_server_ctags.nim"
import "../modules/test_module.nim"
import "../modules/test_module3/test_module3.nim"

proc initModules*() =
  init_module_test_module2()
  init_module_language_server_ctags()
  init_module_test_module()
  init_module_test_module3()
