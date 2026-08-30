# AGENTS.md — omatodolist

> Compact instruction file for OpenCode agents. Every line answers: "Would an agent likely miss this without help?"

## Setup

- Run `git log --oneline -10` to verify the repo state before working.
- `package.json` has no dependencies (npm is a thin runner). Tests run under plain `node` (data layer) and the `quickshell` runtime (QML smokes).
- This repo contains the specification and future implementation for an Omarchy shell plugin (omatodolist: notes + todo list + history in a single UI).

## Architecture & Ownership

- This is a spec-driven project. The design is captured in `docs/spec.md`; implementation follows the SQLite schema and QML bar-widget pattern outlined there.
- Entry points: `BarWidget.qml` (the bar popup), SQLite database at `~/.local/share/omarchy/scratchpad.db`, History tab UI.
- Prohibited: no keyring/secret-tool dependency (per design constraints). Data stored plainly in SQLite.

## Development Workflow

- Typical order (when applicable): implement UI → wire SQLite model → add file watchers → add history tab → test refresh on file change → `npm run validate && npm test`.
- `npm run validate` runs `omarchy plugin validate .`; `npm test` runs validate + the data-layer test + all four QML smokes (Ui, History, Db, Edge) via `scripts/smoke.sh`. Add a new smoke as `X.smoke.qml` and a `test:x` npm script.
- If codegen or migrations are added, run them before `test`.
- The scratchpad plugin is an Omarchy `bar-widget` kind (manifest `kinds: ["bar-widget"]`). QML lives in `BarWidget.qml`; manifest declares `entryPoints.barWidget`.

## Testing

- Data layer: `node test/phase1-db.mjs` (pure JS, no QML). QML behavior: `scripts/smoke.sh <X>.smoke.qml` — it builds a throwaway `qs` import path from `$OMARCHY_SHELL_DIR` (default `/usr/share/omarchy/shell`), gives each smoke its own `XDG_DATA_HOME`, and exits fast by SIGKILLing quickshell once the `SMOKE` verdict prints (`SMOKE_TIMEOUT` caps hangs).
- Refresh behavior should be verified: modify the SQLite file externally and confirm the plugin reloads (`Db.smoke.qml` does exactly this). Also verify panel reopen triggers refresh.
- If snapshots are used, regenerate with the appropriate tool command.

## Common Gotchas

- **Non-refreshing bug**: The original fast-note-todo did not refresh when items were added externally. This plugin **must** use FileWatchers on the SQLite database file to reload on change, and also refresh on panel reopen.
- **Keyring dependency**: Absolutely avoid any secret-keyring or encrypted-secret-storage design. All data is plain SQLite.
- **Inline editor, list-only actions**: There is no overlay composer. The right-hand detail pane *is* the editor (title field + body textarea). `n` (or `a`) starts a new-item draft, `t` with an empty title toggles note/todo, Tab/Enter/Esc leave the editor and **auto-save** (an empty new draft is the only discard path). `space`/`c` (toggle read/done) and `d` (delete, double-press within 2 s confirms) are **list-pane-only** — they must stay inert while the editor fields have focus so they never type text or fire while editing. `c` is the toggle alias only on the main list (on the History tab its `c` = Clear History — different tab, no conflict).
- **Combined list**: Notes and todos share a single unified list sorted by `status` first (pending 0 above done 1) then `updated_at` descending, filtered by type. Do not split into separate panes fixed for notes vs todos.
- **IPC target owner**: The `scratchpad` IpcHandler in `BarWidget.qml` (not the kit Panel) owns the target — `manageIpc: false` disables the kit's handler, and omaplug's BarWidget `refresh()` confirms the pattern. Put data-API methods there; `qs ipc show` lists them (test with `qs ipc -p /usr/share/omarchy/shell show`).
- **IPC `delete` keyword**: `delete` is a JS keyword, so the item-delete IPC method is `remove` (canonical names: `addNote`, `addTodo`, `listNotes`, `listTodos`, `toggleTodo`, `remove`, `clearHistory`; the lifecycle `toggle` takes no args, so the status flip has no `toggle` alias).
- **IPC writes are async**: IpcHandler calls return before the sqlite process finishes; the FileView watcher reload converges the UI + `list*` caches on the write. Agents must wait a short beat between a mutation and re-reading `listNotes`/`listTodos`.

## What to Exclude from This File

- Generic software advice (e.g., "use version control")
- Long tutorials or exhaustive file trees
- Obvious language conventions
- Speculative claims or anything unverified
- Content better stored in another file referenced via `opencode.json` `instructions`