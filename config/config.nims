# This file is for compiling nim plugins to wasm.

--os:linux # Emscripten pretends to be linux.
--cpu:wasm32 # Emscripten is 32bits.
--cc:clang # Emscripten is very close to clang, so we ill replace it.
when defined(windows):
  --clang.exe:emcc.bat  # Replace C
  --clang.linkerexe:emcc.bat # Replace C linker
  --clang.cpp.exe:emcc.bat # Replace C++
  --clang.cpp.linkerexe:emcc.bat # Replace C++ linker.
else:
  --clang.exe:emcc  # Replace C
  --clang.linkerexe:emcc # Replace C linker
  --clang.cpp.exe:emcc # Replace C++
  --clang.cpp.linkerexe:emcc # Replace C++ linker.
--listCmd # List what commands we are running so that we can debug them.

--gc:arc # GC:arc is friendlier with crazy platforms.
--exceptions:goto # Goto exceptions are friendlier with crazy platforms.
--define:noSignalHandler # Emscripten doesn't support signal handlers.
--noMain:on
--threads:off # 1.7.1 defaults this on

--noNimblePath
when withDir(thisDir(), fileExists("../nimble-win.paths")):
  include "../nimble-win.paths"

switch("path", "$nim")
switch("path", "../scripting")
switch("path", "../src")
switch("d", "release")
switch("d", "wasm")
switch("nimcache", "./nimcache")

switch("stackTrace", "on")
switch("lineTrace", "on")

let outputName = projectName() & ".wasm"
# Pass this to Emscripten linker to generate html file scaffold for us.
# No need for main, it's standalone wasm, and we dont need to error on undefined as we're probably importing
switch("passL", "--no-entry -sSTANDALONE_WASM=1 -sERROR_ON_UNDEFINED_SYMBOLS=0 -g")
# switch("passL", "-o wasm/" & outputName)
