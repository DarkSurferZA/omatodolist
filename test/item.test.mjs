import { test } from "node:test"
import assert from "node:assert/strict"
import { loadQmlLib } from "./lib/load-qml-lib.mjs"

const Item = loadQmlLib(new URL("../ui/Item.js", import.meta.url), [
  "isTodo", "isDone", "statusLabel", "toggleVerb", "statusToast", "relativeAge", "indexOfId"
])

const noteUnread = { type: "note", status: 0, title: "Ideas" }
const noteRead = { type: "note", status: 1, title: "Ideas" }
const todoOpen = { type: "todo", status: 0, title: "Buy milk" }
const todoDone = { type: "todo", status: 1, title: "Buy milk" }

test("isTodo / isDone", () => {
  assert.equal(Item.isTodo(noteUnread), false)
  assert.equal(Item.isTodo(todoOpen), true)
  assert.equal(Item.isDone(noteUnread), false)
  assert.equal(Item.isDone(noteRead), true)
  assert.equal(Item.isDone(todoDone), true)
})

test("statusLabel", () => {
  assert.equal(Item.statusLabel(noteUnread), "unread")
  assert.equal(Item.statusLabel(noteRead), "read")
  assert.equal(Item.statusLabel(todoOpen), "open")
  assert.equal(Item.statusLabel(todoDone), "done")
})

test("toggleVerb", () => {
  assert.equal(Item.toggleVerb(noteUnread), "Mark read")
  assert.equal(Item.toggleVerb(noteRead), "Mark unread")
  assert.equal(Item.toggleVerb(todoOpen), "Complete")
  assert.equal(Item.toggleVerb(todoDone), "Reopen")
})

test("statusToast", () => {
  assert.equal(Item.statusToast(noteUnread, 1), "Marked read — Ideas")
  assert.equal(Item.statusToast(noteRead, 0), "Marked unread — Ideas")
  assert.equal(Item.statusToast(todoOpen, 1), "Completed — Buy milk")
  assert.equal(Item.statusToast(todoDone, 0), "Reopened — Buy milk")
})

test("relativeAge: under a minute", () => {
  assert.equal(Item.relativeAge(1000, 1000), "now")
  assert.equal(Item.relativeAge(1000, 1030), "now")
})

test("relativeAge: minutes", () => {
  assert.equal(Item.relativeAge(1000, 1000 + 12 * 60), "12m")
})

test("relativeAge: hours", () => {
  assert.equal(Item.relativeAge(1000, 1000 + 3 * 3600), "3h")
})

test("relativeAge: days", () => {
  assert.equal(Item.relativeAge(1000, 1000 + 2 * 86400), "2d")
})

test("relativeAge: exactly 30 days stays relative", () => {
  assert.equal(Item.relativeAge(0, 30 * 86400), "30d")
})

test("relativeAge: past 30 days falls back to a date", () => {
  const ts = 0
  const now = 31 * 86400
  const d = new Date(ts * 1000)
  const pad = (n) => (n < 10 ? "0" : "") + n
  const expected = d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate())
  assert.equal(Item.relativeAge(ts, now), expected)
})

test("indexOfId finds a row by id, comparing numbers and numeric strings alike", () => {
  const rows = [{ id: 7 }, { id: "12" }, { id: 3 }]
  assert.equal(Item.indexOfId(rows, 12), 1)
  assert.equal(Item.indexOfId(rows, "3"), 2)
  assert.equal(Item.indexOfId(rows, 99), -1)
  assert.equal(Item.indexOfId(null, 1), -1)
})
