.pragma library

// Scratchpad SQL builders + result parsers. Deliberately Quickshell-free (no
// `Quickshell.*`, no QML types) so it's exercised directly under Node (see
// test/db.test.mjs). Owns all SQL for the plugin — views and Db.qml call
// these builders instead of building SQL ad hoc.

// Quote a JS string as a single-quoted SQL literal, doubling embedded quotes.
function q(value) {
  return "'" + String(value).replace(/'/g, "''") + "'"
}

// Escape a substring for use inside a LIKE pattern with backslash escaping.
// Backslashes must be escaped first so they don't swallow the wildcards.
function likeEscape(s) {
  return String(s).replace(/\\/g, "\\\\").replace(/%/g, "\\%").replace(/_/g, "\\_")
}

// Unix timestamp in seconds.
function now() {
  return Math.floor(Date.now() / 1000)
}

// Unified list. filterType is "all"|"note"|"todo";
// query is an optional case-insensitive substring match on title.
// Sort order: pending (unread/in-progress, status 0) always on top, then
// recency — `status ASC, updated_at DESC`.
function listSql(filterType, query) {
  var where = []
  var ft = String(filterType || "all")
  if (ft !== "all") {
    if (ft !== "note" && ft !== "todo") ft = "all"
    else where.push("type = " + q(ft))
  }
  var needle = String(query || "").trim()
  if (needle !== "") {
    var pattern = q("%" + likeEscape(needle) + "%")
    where.push("(title LIKE " + pattern + " ESCAPE '\\' OR body LIKE " + pattern + " ESCAPE '\\')")
  }
  var sql = "SELECT id, type, title, body, status, created_at, updated_at FROM items"
  if (where.length > 0) sql += " WHERE " + where.join(" AND ")
  sql += " ORDER BY status ASC, updated_at DESC, id DESC"
  return sql
}

// Pending counts for the bar badge and the panel header: unread notes /
// in-progress todos, plus unfiltered totals per type for the filter segment.
function countsSql() {
  return "SELECT "
    + "(SELECT COUNT(*) FROM items WHERE type = 'note' AND status = 0) AS unreadNotes, "
    + "(SELECT COUNT(*) FROM items WHERE type = 'todo' AND status = 0) AS inProgressTodos, "
    + "(SELECT COUNT(*) FROM items WHERE type = 'note') AS notes, "
    + "(SELECT COUNT(*) FROM items WHERE type = 'todo') AS todos"
}

// Insert a new item (status 0) + "added" history row, and return its id.
// The `SELECT last_insert_rowid()` sits between the two INSERTs so it captures
// the items row (a later history INSERT would otherwise move last_insert_rowid).
function addSql(type, title, body) {
  var t = (type === "todo") ? "todo" : "note"
  var ts = now()
  var b = (body === null || body === undefined || body === "") ? "NULL" : q(body)
  return "BEGIN;"
    + " INSERT INTO items (type, title, body, status, created_at, updated_at) VALUES ("
    + q(t) + ", " + q(title) + ", " + b + ", 0, " + ts + ", " + ts + ");"
    + " SELECT last_insert_rowid() AS id;"
    + " INSERT INTO history (type, title, action, ts) VALUES ("
    + q(t) + ", " + q(title) + ", 'added', " + ts + ");"
    + " COMMIT;"
}

// Set an item's status (0 or 1) + record "completed"/"reopened" history.
// The history row is an INSERT…SELECT of the item's own type/title so quoting
// is always correct; a missing id records nothing.
function setStatusSql(id, status) {
  var s = (status === 1) ? 1 : 0
  var ts = now()
  var action = (s === 1) ? "completed" : "reopened"
  var nid = Number(id)
  return "BEGIN;"
    + " UPDATE items SET status = " + s + ", updated_at = " + ts + " WHERE id = " + nid + ";"
    + " INSERT INTO history (type, title, action, ts) "
    + "SELECT type, title, " + q(action) + ", " + ts + " FROM items WHERE id = " + nid + ";"
    + " COMMIT;"
}

// Update an item's title/body (bump updated_at, type is fixed on edit) +
// record an "edited" history row carrying the post-edit title. The history
// INSERT…SELECT reads the item's own type + title after the UPDATE.
function updateSql(id, title, body) {
  var nid = Number(id)
  var b = (body === null || body === undefined || body === "") ? "NULL" : q(body)
  var ts = now()
  return "BEGIN;"
    + " UPDATE items SET title = " + q(title) + ", body = " + b + ", updated_at = " + ts
    + " WHERE id = " + nid + ";"
    + " INSERT INTO history (type, title, action, ts) "
    + "SELECT type, title, 'edited', " + ts + " FROM items WHERE id = " + nid + ";"
    + " COMMIT;"
}

// Permanently delete an item + record "deleted" history (title captured first).
function deleteItemSql(id) {
  var ts = now()
  var nid = Number(id)
  return "BEGIN;"
    + " INSERT INTO history (type, title, action, ts) "
    + "SELECT type, title, 'deleted', " + ts + " FROM items WHERE id = " + nid + ";"
    + " DELETE FROM items WHERE id = " + nid + ";"
    + " COMMIT;"
}

// Flip an item's type (note<->todo), bump updated_at, keep status, and
// record a "converted" history row — all in the same transaction.
function convertTypeSql(id) {
  var nid = Number(id)
  var ts = now()
  return "BEGIN;"
    + " UPDATE items SET type = CASE type WHEN 'note' THEN 'todo' ELSE 'note' END, updated_at = " + ts
    + " WHERE id = " + nid + ";"
    + " INSERT INTO history (type, title, action, ts) "
    + "SELECT type, title, 'converted', " + ts + " FROM items WHERE id = " + nid + ";"
    + " COMMIT;"
}

// Newest-first history rows. Capped to keep the table light.
function historySql() {
  return "SELECT id, type, title, action, ts FROM history "
    + "ORDER BY ts DESC, id DESC LIMIT 500"
}

function deleteHistorySql(id) {
  return "DELETE FROM history WHERE id = " + Number(id)
}

function clearHistorySql() {
  return "DELETE FROM history"
}

// Full schema, applied idempotently on first run (every statement uses
// IF NOT EXISTS). Mirrors data/schema.sql, which stays as the human-readable
// reference — this constant is the runtime source of truth: it lives entirely
// inside the JS module, so init() needs no filesystem path for the schema
// (QML file:// and qs:// VFS URLs cannot be handed to the sqlite3 CLI).
var SCHEMA = "CREATE TABLE IF NOT EXISTS items ("
  + "  id INTEGER PRIMARY KEY AUTOINCREMENT,"
  + "  type TEXT NOT NULL,"
  + "  title TEXT NOT NULL,"
  + "  body TEXT,"
  + "  status INTEGER NOT NULL DEFAULT 0,"
  + "  created_at INTEGER NOT NULL,"
  + "  updated_at INTEGER NOT NULL"
  + ");"
  + "CREATE INDEX IF NOT EXISTS idx_items_sort ON items(status, updated_at DESC);"
  + "CREATE INDEX IF NOT EXISTS idx_items_type_status ON items(type, status);"
  + "CREATE TABLE IF NOT EXISTS history ("
  + "  id INTEGER PRIMARY KEY AUTOINCREMENT,"
  + "  type TEXT NOT NULL,"
  + "  title TEXT NOT NULL,"
  + "  action TEXT NOT NULL,"
  + "  ts INTEGER NOT NULL"
  + ");"
  + "CREATE INDEX IF NOT EXISTS idx_history_ts ON history(ts DESC);"

// argv for a read or write via the sqlite3 CLI. `json` enables -json output.
//
// `.timeout 5000` is a CLI dot-command (not SQL) that sets the busy timeout for
// the session: it makes sqlite wait up to 5s on a locked db instead of failing,
// and — unlike `PRAGMA busy_timeout=...` — it prints nothing, so it cannot
// corrupt the -json output.
function sqliteCommand(dbPath, sql, json) {
  var cmd = ["sqlite3"]
  if (json) cmd.push("-json")
  cmd.push(String(dbPath), ".timeout 5000", String(sql))
  return cmd
}

// argv for first-run init: ensure the data dir exists, then apply the schema
// (as a single argv SQL string — $2 is quoted, so the shell cannot mangle it).
function initCommand(dataDir, dbPath) {
  return ["bash", "-c", 'mkdir -p -- "$0" && sqlite3 "$1" "$2"',
    String(dataDir), String(dbPath), SCHEMA]
}

// Parse a `sqlite3 -json` result into an array of row objects (or []).
// An empty result set prints nothing, so "" → [].
function parseRows(text) {
  var t = String(text || "").trim()
  if (t === "") return []
  try {
    var v = JSON.parse(t)
    return Array.isArray(v) ? v : []
  } catch (e) {
    return []
  }
}

// Parse countsSql() output into { unreadNotes, inProgressTodos, notes, todos }.
function parseCounts(text) {
  var rows = parseRows(text)
  var row = rows.length > 0 ? rows[0] : {}
  return {
    unreadNotes: Number(row.unreadNotes) || 0,
    inProgressTodos: Number(row.inProgressTodos) || 0,
    notes: Number(row.notes) || 0,
    todos: Number(row.todos) || 0
  }
}

// Parse addSql() output into the new item's id (-1 if absent). Writes run
// WITHOUT -json, so the output is a plain integer like "2\n".
function parseId(text) {
  var t = String(text || "").trim()
  var n = Number(t)
  return (t !== "" && isFinite(n)) ? n : -1
}
