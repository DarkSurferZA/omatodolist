import { test } from "node:test"
import assert from "node:assert/strict"
import { loadQmlLib } from "./lib/load-qml-lib.mjs"

const Db = loadQmlLib(new URL("../data/Db.js", import.meta.url), [
  "q", "likeEscape", "now", "listSql", "countsSql", "addSql", "setStatusSql",
  "updateSql", "deleteItemSql", "convertTypeSql", "historySql", "deleteHistorySql",
  "clearHistorySql", "SCHEMA", "sqliteCommand", "initCommand", "parseRows", "parseCounts",
  "parseId"
])

function withFixedNow(ms, fn) {
  const real = Date.now
  Date.now = () => ms
  try {
    return fn()
  } finally {
    Date.now = real
  }
}

test("listSql: no filter, no query", () => {
  assert.equal(
    Db.listSql("all", ""),
    "SELECT id, type, title, body, status, created_at, updated_at FROM items ORDER BY status ASC, updated_at DESC, id DESC"
  )
})

test("listSql: type filter only", () => {
  assert.equal(
    Db.listSql("todo", ""),
    "SELECT id, type, title, body, status, created_at, updated_at FROM items WHERE type = 'todo' ORDER BY status ASC, updated_at DESC, id DESC"
  )
})

test("listSql: query matches title or body", () => {
  assert.equal(
    Db.listSql("all", "cafe"),
    "SELECT id, type, title, body, status, created_at, updated_at FROM items "
      + "WHERE (title LIKE '%cafe%' ESCAPE '\\' OR body LIKE '%cafe%' ESCAPE '\\') "
      + "ORDER BY status ASC, updated_at DESC, id DESC"
  )
})

test("countsSql: unread/in-progress plus unfiltered totals per type", () => {
  assert.equal(
    Db.countsSql(),
    "SELECT (SELECT COUNT(*) FROM items WHERE type = 'note' AND status = 0) AS unreadNotes, "
      + "(SELECT COUNT(*) FROM items WHERE type = 'todo' AND status = 0) AS inProgressTodos, "
      + "(SELECT COUNT(*) FROM items WHERE type = 'note') AS notes, "
      + "(SELECT COUNT(*) FROM items WHERE type = 'todo') AS todos"
  )
})

test("convertTypeSql", () => {
  const sql = withFixedNow(1700000000000, () => Db.convertTypeSql(3))
  assert.equal(
    sql,
    "BEGIN; UPDATE items SET type = CASE type WHEN 'note' THEN 'todo' ELSE 'note' END, updated_at = 1700000000 WHERE id = 3; "
      + "INSERT INTO history (type, title, action, ts) SELECT type, title, 'converted', 1700000000 FROM items WHERE id = 3; COMMIT;"
  )
})

test("historySql", () => {
  assert.equal(
    Db.historySql(),
    "SELECT id, type, title, action, ts FROM history ORDER BY ts DESC, id DESC LIMIT 500"
  )
})

test("deleteHistorySql", () => {
  assert.equal(Db.deleteHistorySql(5), "DELETE FROM history WHERE id = 5")
})

test("clearHistorySql", () => {
  assert.equal(Db.clearHistorySql(), "DELETE FROM history")
})

test("addSql: todo with empty body", () => {
  const sql = withFixedNow(1700000000000, () => Db.addSql("todo", "Buy milk", ""))
  assert.equal(
    sql,
    "BEGIN; INSERT INTO items (type, title, body, status, created_at, updated_at) VALUES "
      + "('todo', 'Buy milk', NULL, 0, 1700000000, 1700000000); SELECT last_insert_rowid() AS id; "
      + "INSERT INTO history (type, title, action, ts) VALUES ('todo', 'Buy milk', 'added', 1700000000); COMMIT;"
  )
})

test("setStatusSql: marking complete", () => {
  const sql = withFixedNow(1700000000000, () => Db.setStatusSql(3, 1))
  assert.equal(
    sql,
    "BEGIN; UPDATE items SET status = 1, updated_at = 1700000000 WHERE id = 3; "
      + "INSERT INTO history (type, title, action, ts) SELECT type, title, 'completed', 1700000000 FROM items WHERE id = 3; COMMIT;"
  )
})

test("updateSql: title and body", () => {
  const sql = withFixedNow(1700000000000, () => Db.updateSql(3, "New title", "body text"))
  assert.equal(
    sql,
    "BEGIN; UPDATE items SET title = 'New title', body = 'body text', updated_at = 1700000000 WHERE id = 3; "
      + "INSERT INTO history (type, title, action, ts) SELECT type, title, 'edited', 1700000000 FROM items WHERE id = 3; COMMIT;"
  )
})

test("deleteItemSql", () => {
  const sql = withFixedNow(1700000000000, () => Db.deleteItemSql(3))
  assert.equal(
    sql,
    "BEGIN; INSERT INTO history (type, title, action, ts) SELECT type, title, 'deleted', 1700000000 FROM items WHERE id = 3; "
      + "DELETE FROM items WHERE id = 3; COMMIT;"
  )
})

test("parseRows: empty text", () => {
  assert.deepEqual(Db.parseRows(""), [])
})

test("parseRows: valid json array", () => {
  assert.deepEqual(Db.parseRows('[{"a":1}]'), [{ a: 1 }])
})

test("parseRows: garbage falls back to []", () => {
  assert.deepEqual(Db.parseRows("not json"), [])
})

test("parseCounts", () => {
  assert.deepEqual(
    Db.parseCounts('[{"unreadNotes":2,"inProgressTodos":5,"notes":4,"todos":6}]'),
    { unreadNotes: 2, inProgressTodos: 5, notes: 4, todos: 6 }
  )
})

test("parseId: plain integer output", () => {
  assert.equal(Db.parseId("42\n"), 42)
})

test("parseId: empty output", () => {
  assert.equal(Db.parseId(""), -1)
})

test("sqliteCommand: json read", () => {
  assert.deepEqual(
    Db.sqliteCommand("/tmp/db", "SELECT 1", true),
    ["sqlite3", "-json", "/tmp/db", ".timeout 5000", "SELECT 1"]
  )
})

test("sqliteCommand: plain write", () => {
  assert.deepEqual(
    Db.sqliteCommand("/tmp/db", "DELETE FROM history", false),
    ["sqlite3", "/tmp/db", ".timeout 5000", "DELETE FROM history"]
  )
})

test("initCommand", () => {
  assert.deepEqual(
    Db.initCommand("/tmp/dir", "/tmp/dir/db.sqlite"),
    ["bash", "-c", 'mkdir -p -- "$0" && sqlite3 "$1" "$2"', "/tmp/dir", "/tmp/dir/db.sqlite", Db.SCHEMA]
  )
})

test("q doubles single quotes", () => {
  assert.equal(Db.q("Jane's"), "'Jane''s'")
})

test("likeEscape escapes the backslash first, then the wildcards", () => {
  assert.equal(Db.likeEscape("50%_a\\b"), "50\\%\\_a\\\\b")
})

test("listSql neutralizes a quote and a wildcard in the search text", () => {
  assert.equal(
    Db.listSql("all", "it's 100%"),
    "SELECT id, type, title, body, status, created_at, updated_at FROM items"
    + " WHERE (title LIKE '%it''s 100\\%%' ESCAPE '\\' OR body LIKE '%it''s 100\\%%' ESCAPE '\\')"
    + " ORDER BY status ASC, updated_at DESC, id DESC")
})
