# Harpoon

**Work in progress**

Harpoon is a builtin plugin which aims to provide fast navigation.
It is based on the Neovim plugin [Harpoon](https://github.com/ThePrimeagen/harpoon/tree/harpoon2).

Currently there are no keybindings for harpoon by default.

Here is an example config you can put into your `keybindings.json`
```json
// ~/.nev/keybindings.json
{
    "editor": {
        "<C-a>": "harpoon-list-add", // Add the current file to the default list
        "<C-g><C-g><C-h>": "harpoon-list-set 0", // Store the current file at index 0 in the default list
        "<C-g><C-g><C-j>": "harpoon-list-set 1",
        "<C-g><C-g><C-k>": "harpoon-list-set 2",
        "<C-g><C-g><C-l>": "harpoon-list-set 3",
        "<C-g><C-h>": "harpoon-list-select 0", // Jump to the file at index 0 in the default list
        "<C-g><C-j>": "harpoon-list-select 1",
        "<C-g><C-k>": "harpoon-list-select 2",
        "<C-g><C-l>": "harpoon-list-select 3"
    }
}
```