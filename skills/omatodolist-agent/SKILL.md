---
name: omatodolist-agent
description: >
  Read/write the user's notes and todos via the omatodolist Omarchy bar-widget
  plugin (SQLite-backed, IPC-driven). Use when the user says "add a note",
  "note that…", "remember this", "what's on my todo list", "mark X done",
  "delete X", "clear the history", or asks to open/close the omatodolist panel.
  Also for passive capture: saving short reminders and task outcomes during a
  conversation. Talks through the `omatodolist` helper below; never touch the
  SQLite db file directly (that bypasses the plugin's file watchers and the
  panel goes stale).
---

# omatodolist — notes + todos via IPC

One command, `omatodolist <method> [args...]` — the helper at
`bin/omatodolist` in this skill. It finds the running omarchy shell, forwards
to the `scratchpad` IPC target, and prints JSON on stdout.

## Data model

SQLite rows: `{id, type, title, body, status}`

- **`type`**: `note` or `todo`. Notes are free-form entries (title + optional
  body); todos are actionable items. Both live in one unified list in the panel
  (pending above done), filterable by type.
- **`status`**: `0` = pending/unread, `1` = done/read. `toggleTodo <id>` flips
  it for both types.
- **`remove <id>` is permanent** — there is no undo tray or retention window.
  Verify the id before removing; if a substring matches multiple rows, present
  them and ask which one.

## Round-trip every change

Mutations are async by design: the call acks `{"ok":true}` immediately, then
the plugin's file watcher converges. The helper sleeps a beat after a write, so
each command ends already-converged. Still, close every change by re-reading:

1. Read the current state: `omatodolist listNotes` and `omatodolist listTodos`.
2. Apply the change with one method (table below).
3. Re-read and confirm it landed — the done condition is the list reflecting
   the flip, removal, or new row you intended.

## Methods

| Method | Args | Effect |
|---|---|---|
| `open` / `close` / `toggle` / `show` / `hide` | — | panel visibility (no args) |
| `ping` | — | sanity: prints `ok` |
| `addNote` / `addTodo` | exactly two: `<title>` `<body>` | new pending item (status 0) |
| `listNotes` / `listTodos` | — | JSON rows `{id,type,title,body,status}` |
| `toggleTodo` | `<id>` | flip status: 0 ↔ 1 (in-progress/unread ↔ done/read) |
| `remove` | `<id>` | permanently delete the row |
| `clearHistory` | — | wipe the History tab |

## Substring matching (the helper works on ids)

For "mark X done" / "delete X" style requests:

1. `omatodolist listTodos` (or `listNotes`) — JSON rows.
2. Case-insensitive substring match against `title` + `body`.
3. Exactly one match → act on its id. Multiple matches → list them and ask the
   user which. Zero matches → say so; never guess a near-match.

There is **no IPC edit endpoint** — edits happen in the panel's inline editor.
To rewrite an entry from the CLI: `remove <id>` then `addNote`/`addTodo` with
the new text (removal is permanent, so confirm before rewriting). To append to
a note's body: read it, remove it, re-add with the combined text.

## Ownership: the `pv-` prefix rule

When **reading** the todo list, ownership is decided by a prefix:

- **No `pv-` prefix** → the item belongs to **the user (the Emperor)**. It is
  *their* task. **NEVER** treat it as work for me to perform, and never "take
  on" or complete it on their behalf. I may only manage it (list, check off,
  delete) when the user explicitly asks.
- **`pv-` prefix** (e.g. `pv-check for system errors`) → the item is a task for
  **me (Petronella)** to carry out. When I see one, it is an instruction to me.

In short: **only `pv-` items are mine to act on. Every other item is the
user's.** Do not conflate the two, and never assume an unprefixed item is
something I should do.

## Routing rules (agent → where to write)

**Use omatodolist when:**
- User explicitly says "note it" / "add a todo" / "remember this".
- A big task is **finished** → `addNote "<task>" "<outcome summary>"`.
- Something **failed and needs the user** (key expired, permission denied,
  backup didn't run) → `addTodo "Refresh X — failed on <date>" ""`.
- A **short, actionable reminder** surfaces during a conversation ("buy X",
  "call Y back") → `addTodo "..." ""`.
- A **big project with sub-tasks** is being set up →
  `addTodo "Project X — see Obsidian" ""` + full breakdown in Obsidian.
- User is away and needs a **message/assignment** → `addNote "..." ""`.

**Use Obsidian when:**
- Journaling, diary entries, long-form reflection.
- Detailed project breakdowns with many sub-tasks.
- Knowledge that should be searchable, linked, and durable.

**Do NOT write to omatodolist when:**
- The content is purely my internal working state (use the built-in `todo`
  tool for session-scoped agent tasks).
- The item already exists — list first; prefer not to add duplicates.

## Passive capture protocol (auto-save, then tell)

When something matches the routing rules **during** a conversation (not only on
explicit request):

1. Write it using the helper (`addNote` / `addTodo`).
2. **In the same response**, briefly mention:
   > *Saved to your notes: "…"* or *Added to your todos: "…"*
3. Do NOT ask permission first — the user chose auto-save-and-tell.
4. If the user says "no, don't save that" / "remove that": find it by substring
   and `remove <id>` immediately. Removal is permanent, so when a match is
   ambiguous, confirm the exact row before deleting.

## Safety

- **IPC only.** Never edit `~/.local/share/omarchy/scratchpad.db` directly —
  direct writes bypass the plugin's file watchers and leave the panel stale.
- No locking or cache problems: writes converge via the plugin's FileWatcher,
  and the panel refreshes on reopen. There is no need to close the panel first
  or restart the shell after a write.

## Error handling

- Helper exits 1 with `no running omarchy shell` → the bar/shell isn't up. Tell
  the user; retry once they confirm the desktop session is active.
- IPC call fails or returns non-JSON → show the raw output and do not blind-retry
  more than once.

## Gotchas (IPC specifics)

- **`addNote`/`addTodo` take exactly two args** — pass `""` for an empty body.
- The bare `toggle` is panel visibility only; the status flip is
  `toggleTodo <id>`. Removal is **`remove`** (`delete` is a JS keyword).
- The IPC channel name is **`scratchpad`**; "omatodolist" is the display name.

## Relationship to other skills

| Skill | Role |
|-------|------|
| **Obsidian** (`note-taking/obsidian`) | Long-form, durable, linked notes. Promote omatodolist items here when they grow. |
| **weekly-review-planning** / **meeting-action-items** / **document-to-action-items** | May optionally drop a single-line summary into omatodolist as a quick note/todo (one short line only; full detail stays in their own tracker). |
| **`todo` tool (built-in)** | Agent's own session-scoped working list. NOT the user's personal list. |

omatodolist is the **fast, short, at-a-glance** store. Obsidian is the **deep,
searchable, durable** store. They complement each other.
