.pragma library

// Item semantics — the single place that reads `type`/`status` off a row.
// Views call these instead of repeating `Number(x.status) === 1` and the
// note/todo ternaries.

function isTodo(item) {
  return !!item && item.type === "todo"
}

function isDone(item) {
  return !!item && Number(item.status) === 1
}

// "open" | "done" (todos) or "unread" | "read" (notes).
function statusLabel(item) {
  if (!item) return ""
  if (isTodo(item)) return isDone(item) ? "done" : "open"
  return isDone(item) ? "read" : "unread"
}

// Label for the button that flips status.
function toggleVerb(item) {
  if (!item) return ""
  if (isTodo(item)) return isDone(item) ? "Reopen" : "Complete"
  return isDone(item) ? "Mark unread" : "Mark read"
}

// Toast text after `item`'s status is set to `status` (0 or 1).
function statusToast(item, status) {
  if (!item) return ""
  var done = Number(status) === 1
  var verb = isTodo(item)
    ? (done ? "Completed" : "Reopened")
    : (done ? "Marked read" : "Marked unread")
  return verb + " — " + item.title
}

// "now", "12m", "3h", "2d", or "YYYY-MM-DD" once the age passes 30 days.
function relativeAge(tsSeconds, nowSeconds) {
  var delta = Math.max(0, Number(nowSeconds) - Number(tsSeconds))
  if (delta < 60) return "now"
  var minutes = Math.floor(delta / 60)
  if (minutes < 60) return minutes + "m"
  var hours = Math.floor(minutes / 60)
  if (hours < 24) return hours + "h"
  var days = Math.floor(hours / 24)
  if (days <= 30) return days + "d"
  var d = new Date(Number(tsSeconds) * 1000)
  function pad(n) { return (n < 10 ? "0" : "") + n }
  return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate())
}

function indexOfId(rows, id) {
  var list = rows || []
  for (var i = 0; i < list.length; ++i)
    if (Number(list[i].id) === Number(id)) return i
  return -1
}
