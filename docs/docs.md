# Nev documentation

This file contains documentation about features that don't fit into any of the other docs.
- [Build from source](docs/building_from_source.md)
- [Getting started](docs/getting_started.md)
- [Cheatsheet](docs/cheatsheet.md)
- [Configuration](docs/configuration.md)
- [Finders](docs/finders.md)
- [Plugin API](https://nimaoth.github.io/AbsytreeDocs/scripting_nim/htmldocs/theindex.html).
- [Virtual filesystem](docs/virtual_file_system.md)

## Command aliases

To create an alias for a command add this to a config file:

```json
// settings.json
{
  "alias.q": "quit",
  "alias.wq": ["write-file", "quit"],

  // alternative syntax (use + to add new aliases without deleting existing ones defined in prior configs):
  "+alias": {
    "q": "quit",
    "wq": ["write-file", "quit"],
  }
}
```

This defines two aliases `w` and `wq`. When you run the `w` command it will run `quit`,
and if you run `wq` then it will run `write-file` and then `quit`.

Aliases can use other aliases, so the following is possible:

```json
// settings.json
{
  "alias.q": "quit",
  "alias.wq": ["write-file", "q"],
}
```

Aliases can be bound to keys, so the following will run the `wq` alias when pressing `<SPACE>wq`:

```json
// keybindings.json
{
    "editor": {
        "<SPACE>wq": "wq",
    },
}
```

You can specify parameters and forward parameters in aliases:

```json
// settings.json
{
  "alias.q": "quit-immediately 1",
  "alias.wq": ["write-file @0", "quit-immediately @1"],
  "alias.echo": [
    // the echo-args command just logs all arguments to the log file
    "echo-args @0 @1",
    "echo-args @",
    "echo-args @@"
  ],
}
```

`@@` refers to all arguments, `@n` refers to the nth argument and `@` refers to the remaining arguments after the previous `@n` (or all arguments if there is no `@n` before)

The remaining arguments for `@` are tracked across multiple commands, so in this example the second `echo-args` command
doesn't receive any arguments if you only pass two arguments to the alias, because the first command already consumes both.

You can use the same indices for `@n` multiple times.

Here are some examples of running these aliases and the commands that will be executed:
- `q` -> `quit-immediately 1`
- `wq "test.txt" 1` -> `write-file "test.txt"`, `quit-immediately 1`
- `echo "a" "b"` -> `echo-args "a" "b"`, `echo-args`, `echo-args "a" "b"`
- `echo "a" "b" "c" "d"` -> `echo-args "a" "b"`, `echo-args "c" "d"`, `echo-args "a" "b" "c" "d"`
