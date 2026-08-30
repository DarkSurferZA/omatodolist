# omatodolist

A keyboard-driven **notes + todo list + history** plugin for the Omarchy shell, shipped as a `bar-widget`. Short notes and todos share one unified list, sorted pending-first then by most-recent, and every change is persisted to an on-disk SQLite database. The plugin watches that database file and refreshes automatically when it changes elsewhere (or when the panel reopens), so the UI never goes stale.

## Features

- **Unified list** — notes and todos in a single list, sorted `status` first (pending/in-progress above read/completed) then `updated_at` descending.
- **Panel = the editor** — the right-hand detail pane is your inline editor: a title field plus a body textarea. There is no separate overlay composer.
- **Keyboard-driven** — `n`/`a` starts a new draft, `t` toggles note/todo, `space`/`c` toggles read/done, `d` deletes (double-press within 2 s confirms). Tab/Enter/Esc leave the editor and auto-save.
- **History tab** — a read-only mutation log (`added`, `completed`, `reopened`, `deleted`), newest first, with Clear History.
- **SQLite-backed with file-watcher auto-refresh** — the database is the source of truth; external edits and panel reopens both trigger a reload.
- **IPC API** — add, list, toggle, remove, and clear entries over the `scratchpad` IpcHandler target, so the plugin can be driven from the shell (`qs ipc -p /usr/share/omarchy/shell`).

## Install

```sh
omarchy plugin add https://github.com/DarkSurferZA/omatodolist.git --enable
```

## Remove

```sh
omarchy plugin remove io.github.darksurferza.omatodolist
```

## Usage

Click the bar icon (the notepad-with-text glyph) to open the panel, or use the IPC methods:

- `addNote(title[, body])` — add a note
- `addTodo(title[, body])` — add a todo
- `listNotes()` / `listTodos()` — JSON list of items
- `toggleTodo(id)` — flip a todo between in-progress and completed
- `remove(id)` — delete an item
- `clearHistory()` — wipe the history log

Every mutation is async and converges on the UI through the file watcher.

## Data

- **Database**: SQLite at `~/.local/share/omarchy/scratchpad.db`
- **Schema**: `data/schema.sql` (an `items` table for notes/todos and a `history` mutation log)
- Stored plainly — no keyring or encrypted-secret dependency.

## Development

- `npm run validate` — `omarchy plugin validate .`

## Skills

The `skills/omatodolist-agent/` directory contains an OpenCode agent skill for driving the plugin via IPC from the command line. Install it by copying the `skills/omatodolist-agent` folder into your agent's skills directory.

## License

[Apache License 2.0](LICENSE)

Copyright © 2026 Cailan Sacks

## AI Disclosure

Parts of this package, including code and this documentation, were developed with the assistance of AI tools (OpenCode) working from the project specification under human direction.
