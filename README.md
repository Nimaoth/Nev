# Absytree

This is still very early in developement and very experimental!

## Programming Language + Editor

Absytree is a programming languange where instead of writing the source code as text in text files,
the abstract syntac tree (AST) is edited directly by a custom editor.

## Building

- `nim c -d:mingw -d:release -o:ast.exe --mm:refc --passL:-llibstdc++ ./src/absytree.nim`
- It currently dynamically links against libstdc++ because some treesitter languages depend on that, so:
  - On windows: copy `libgcc_s_seh-1.dll` and `libstdc++-6.dll` (and optionally `libwinpthread-1.dll`) to the exe directory

## Screenshots

![alt](screenshots/screenshot1.png)
![alt](screenshots/screenshot2.png)
![alt](screenshots/screenshot3.png)
![alt](screenshots/screenshot4.png)