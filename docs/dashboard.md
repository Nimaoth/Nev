# Dashboard

The dashboard is shown when no other view is active. It displays a customizable set of sections
including commands, recent sessions, git status, and commit history.

## Overview

The dashboard layout consists of sections arranged in a two-column grid (or single column on
narrow screens). Each section has a header and displays content based on its type.

### Default Sections

| Section | Column | Description |
|---------|--------|-------------|
| Logo | Full width | ASCII art logo with random ANSI color |
| Commands | Left | Shows commands and their keybindings |
| Sessions | Left | Lists recent sessions with quick-open keys |
| Git Status | Right | Shows uncommitted file changes |
| Commit History | Right | Shows recent git commits |

## Configuration

Customize settings in `~/.nev/settings.json`. See [settings.md](settings.md) for how settings
work.

### Layout Settings

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `dashboard.min-two-col-chars` | int | 160 | Minimum width in characters for two-column layout |
| `dashboard.pad-x` | float | 0.02 | Horizontal padding as fraction of width (0-1) |
| `dashboard.pad-y` | float | 0.02 | Vertical padding as fraction of height (0-1) |
| `dashboard.section-gap` | float | 0.01 | Gap between sections as fraction of height (0-1) |
| `dashboard.col-gap` | float | 0.02 | Gap between columns as fraction of width (0-1) |

### Section Configuration

Sections are configured via the `dashboard.sections` setting. Each key in the object defines a
section, with the value being the section properties:

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `name` | string | (required) | Section type (see below) |
| `title` | string | same as name | Section header title |
| `side` | int | 0 | Column: -1 = full width, 0 = left, 1 = right |
| `border` | bool | true | Whether to draw a border around the section |
| `maxItems` | int | varies | Maximum number of items to display |

#### Section Types

- `logo` - ASCII art logo. Supports a custom `logos` property (array of array of strings)
  to define custom ASCII art. Falls back to built-in logos.
- `commands` - Command list with keybindings
- `sessions` - Recent sessions list
- `gitStatus` - Git file status
- `commitHistory` - Git commit log

#### Logo

The `logo` type displays ASCII art with a random ANSI color. Custom logos can be defined using the
`logos` property:

```json
{
  "name": "logo",
  "border": false,
  "logos": [
    [
      " _   _  _____  _____ ",
      "| \\ | ||  ___||  ___|",
      "|  \\| || |__  | |__  ",
      "|     ||  __| |  __| ",
      "| |\\  || |___ | |___ ",
      "\\_| \\_/\\____/ \\____/ "
    ]
  ]
}
```

Each entry in the `logos` array is an array of strings representing the lines of one logo.
One logo is randomly selected on each load.

#### Commands

The `commands` type reads its command list from the `commands` field:

```json
{
  "name": "commands",
  "title": "Commands",
  "side": 0,
  "commands": ["command-line", "explore-help", "choose-file", "choose-open"]
}
```

Each command name is looked up in the active keybinding contexts (determined by
`editor.base-modes`). All matching keys are displayed, sorted by length, with
shortest first.

#### Sessions

The `sessions` type shows recent sessions. Keybindings for `dashboard.session.open <index>`
are displayed next to each session.

#### Git Sections

`gitStatus` and `commitHistory` fetch data asynchronously. Use `maxItems` to limit the
number of entries displayed (defaults: gitStatus=25, commitHistory=50).

### Example Configuration

```json
{
  "dashboard.pad-x": 0.03,
  "dashboard.pad-y": 0.02,
  "dashboard.col-gap": 0.01,
  "dashboard.sections": {
    "logo": { "name": "logo", "title": "", "border": false },
    "commands": {
      "name": "commands",
      "title": "Commands",
      "side": 0,
      "commands": ["command-line", "choose-file", "explore-files", "quit"]
    },
    "sessions": {
      "name": "sessions",
      "title": "Recent Sessions",
      "side": 0,
      "maxItems": 5
    },
    "gitStatus": {
      "name": "gitStatus",
      "title": "Git Status",
      "side": 1,
      "maxItems": 20
    },
    "commitHistory": {
      "name": "commitHistory",
      "title": "Commits",
      "side": 1,
      "maxItems": 30
    }
  }
}
```

## Commands

| Commands | Arguments | Description |
|--------|-----------|-------------|
| `dashboard.session.open` | index (int) | Open recent session at index |
| `dashboard.logo.randomize` | none | Randomize logo style and color |

Example keybindings (in the `dashboard` context):

```json
{
  "dashboard": {
    "1": ["dashboard.session.open 0"],
    "2": ["dashboard.session.open 1"],
    "3": ["dashboard.session.open 2"],
    "r": ["dashboard.logo.randomize"]
  }
}
```
