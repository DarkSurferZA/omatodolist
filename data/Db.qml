import QtQuick
import Quickshell
import Quickshell.Io
import "Db.js" as Db

// Scratchpad data layer — the single entry point for all database access.
//
// Views (BarWidget.qml, Panel.qml) never build SQL or touch sqlite3 directly:
// they instantiate this component and call its methods. All SQL lives in
// Db.js (pure, Node-testable); this component owns the sqlite3 `Process`es,
// the `FileView` change watcher (spec §4), and the cached state that the UI
// binds to.
//
// Lifecycle:
//   Component.onCompleted -> init()            (mkdir + apply schema, idempotent)
//   init done             -> load()            (counts + list + history)
//   file changed (any)    -> debounced load()  (our writes AND external edits)
//
// Writes are serialized (one at a time); reads use one dedicated Process each
// so counts/list/history refresh independently. Every mutation appends its
// history row inside the same BEGIN…COMMIT (see Db.js).
QtObject {
    id: root

    // ------------------------------------------------------------------ paths
    // $XDG_DATA_HOME/omarchy, falling back to ~/.local/share/omarchy (spec §5).
    readonly property string dataDir: {
        var xdg = Quickshell.env("XDG_DATA_HOME")
        if (xdg && String(xdg) !== "") return String(xdg) + "/omarchy"
        return String(Quickshell.env("HOME")) + "/.local/share/omarchy"
    }
    readonly property string dbPath: root.dataDir + "/scratchpad.db"

    // ------------------------------------------------------------------ state
    property bool ready: false                 // init() completed
    property string lastError: ""

    // Cached rows (populated by reads; the UI binds to these).
    property var items: []                     // list() results
    property var history: []                   // historyList() results
    property int unreadNotes: 0                // notes with status 0
    property int inProgressTodos: 0            // todos with status 0

    // Last list() filter, remembered so load() can re-fetch the same subset
    // after a change (the panel sets these in Phase 2).
    property string listFilter: "all"
    property string listQuery: ""

    // ------------------------------------------------------------------ signals
    signal initialized()
    signal itemsUpdated(var items)
    signal countsUpdated()
    signal historyUpdated(var history)
    signal added(int id)
    signal statusChanged(int id, int status)
    signal updated(int id)
    signal itemDeleted(int id)
    signal historyRowDeleted(int id)
    signal historyCleared()
    signal failed(string message)

    // ------------------------------------------------------------------ errors
    // Central failure path: surfaces in the journal (console.error) so data-layer
    // errors are visible in the shell logs even before the UI handles them.
    function fail(message) {
        root.lastError = message
        console.error("scratchpad db: " + message)
        root.failed(message)
    }

    // ------------------------------------------------------------------ reads
    property Process countsProcess: Process {
        stdout: StdioCollector {
            id: countsStdout
            waitForEnd: true
        }
        onExited: function(exitCode) {
            if (exitCode !== 0) {
                root.fail("counts read failed (exit " + exitCode + ")")
                return
            }
            var c = Db.parseCounts(countsStdout.text)
            root.unreadNotes = c.unreadNotes
            root.inProgressTodos = c.inProgressTodos
            root.countsUpdated()
        }
    }

    property Process listProcess: Process {
        stdout: StdioCollector {
            id: listStdout
            waitForEnd: true
        }
        onExited: function(exitCode) {
            if (exitCode !== 0) {
                root.fail("list read failed (exit " + exitCode + ")")
                return
            }
            var rows = Db.parseRows(listStdout.text)
            root.items = rows
            root.itemsUpdated(rows)
        }
    }

    property Process historyProcess: Process {
        stdout: StdioCollector {
            id: historyStdout
            waitForEnd: true
        }
        onExited: function(exitCode) {
            if (exitCode !== 0) {
                root.fail("history read failed (exit " + exitCode + ")")
                return
            }
            var rows = Db.parseRows(historyStdout.text)
            root.history = rows
            root.historyUpdated(rows)
        }
    }

    // ------------------------------------------------------------------ writes
    property string _writeKind: ""
    property var _writeArgs: null

    property Process writeProcess: Process {
        stdout: StdioCollector {
            id: writeStdout
            waitForEnd: true
        }
        onExited: function(exitCode) {
            var kind = root._writeKind
            var args = root._writeArgs
            root._writeKind = ""
            root._writeArgs = null

            if (exitCode !== 0) {
                var err = String(writeStdout.text || "").trim()
                if (err === "") err = "sqlite3 exited " + exitCode
                root.fail(err)
                return
            }

            if (kind === "init") {
                root.ready = true
                root.initialized()
                // (Re)bind the watcher now that the file exists, then load.
                dbFile.reload()
                root.load()
            } else {
                if (kind === "add") root.added(Db.parseId(writeStdout.text))
                else if (kind === "setStatus") root.statusChanged(args.id, args.status)
                else if (kind === "update") root.updated(args.id)
                else if (kind === "deleteItem") root.itemDeleted(args.id)
                else if (kind === "deleteHistory") root.historyRowDeleted(args.id)
                else if (kind === "clearHistory") root.historyCleared()
                // Belt and braces next to the file watcher: our own write just
                // changed the file, so refresh shortly (also covers the edge
                // case where the watcher misses our own modification).
                postWriteReload.restart()
            }
        }
    }

    function _write(kind, sql, args) {
        if (root.writeProcess.running) {
            root.fail("database busy — try again")
            return
        }
        root._writeKind = kind
        root._writeArgs = args
        root.writeProcess.command = Db.sqliteCommand(root.dbPath, sql, false)
        root.writeProcess.running = true
    }

    // ------------------------------------------------------------------ file watcher (spec §4)
    // Watches the db file; any change — external sqlite3 edits, other tools,
    // or our own writes — triggers a debounced reload. No timer polling.
    // QtObject has no default property, so these are explicit properties
    // (same pattern as the Process objects above) rather than inline children.
    property FileView dbFile: FileView {
        path: root.dbPath
        watchChanges: true
        printErrors: false
        onFileChanged: {
            if (!root.ready) return
            externalReloadDebounce.restart()
        }
    }

    property Timer externalReloadDebounce: Timer {
        interval: 250
        repeat: false
        onTriggered: root.load()
    }

    property Timer postWriteReload: Timer {
        interval: 80
        repeat: false
        onTriggered: root.load()
    }

    // ------------------------------------------------------------------ public API

    // Create the data dir + apply the schema (idempotent). Call once at start.
    function init() {
        if (root.ready) return
        if (root.writeProcess.running) return
        root._writeKind = "init"
        root._writeArgs = null
        root.writeProcess.command = Db.initCommand(root.dataDir, root.dbPath)
        root.writeProcess.running = true
    }

    // Current pending counts (spec §3.2).
    function counts() {
        return { unreadNotes: root.unreadNotes, inProgressTodos: root.inProgressTodos }
    }

    function loadCounts() {
        if (!root.ready || root.countsProcess.running) return
        root.countsProcess.command = Db.sqliteCommand(root.dbPath, Db.countsSql(), true)
        root.countsProcess.running = true
    }

    // Unified list (spec §3.1). filterType: "all"|"note"|"todo"; query: title substring.
    function list(filterType, query) {
        if (!root.ready || root.listProcess.running) return
        root.listFilter = String(filterType || "all")
        root.listQuery = String(query || "")
        root.listProcess.command = Db.sqliteCommand(root.dbPath, Db.listSql(filterType, query), true)
        root.listProcess.running = true
    }

    function historyList() {
        if (!root.ready || root.historyProcess.running) return
        root.historyProcess.command = Db.sqliteCommand(root.dbPath, Db.historySql(), true)
        root.historyProcess.running = true
    }

    // Re-fetch everything with the last list() filter (used by the watcher,
    // after writes, and as the reopen safety net — spec §4).
    function load() {
        root.loadCounts()
        root.list(root.listFilter, root.listQuery)
        root.historyList()
    }

    // ------------------------------------------------------------------ mutations

    // Add a note/todo (status 0) + "added" history. Emits added(id).
    function add(type, title, body) {
        if (!root.ready) return
        var t = String(title || "").trim()
        if (t === "") {
            root.fail("add: empty title")
            return
        }
        root._write("add", Db.addSql(type === "todo" ? "todo" : "note", t, body), null)
    }

    // Set status (0 or 1) + "completed"/"reopened" history. Emits statusChanged(id, status).
    function setStatus(id, status) {
        if (!root.ready) return
        var s = status === 1 ? 1 : 0
        root._write("setStatus", Db.setStatusSql(id, s), { id: Number(id), status: s })
    }

    // Update an item's title/body (type is fixed on edit) + "edited" history.
    // Emits updated(id). Empty title is rejected (the field is required).
    function update(id, title, body) {
        if (!root.ready) return
        var t = String(title || "").trim()
        if (t === "") {
            root.fail("update: empty title")
            return
        }
        root._write("update", Db.updateSql(id, t, body), { id: Number(id) })
    }

    // Permanently delete an item + "deleted" history. Emits itemDeleted(id).
    function deleteItem(id) {
        if (!root.ready) return
        root._write("deleteItem", Db.deleteItemSql(id), { id: Number(id) })
    }

    // Delete one history row. Emits historyRowDeleted(id).
    function deleteHistory(id) {
        if (!root.ready) return
        root._write("deleteHistory", Db.deleteHistorySql(id), { id: Number(id) })
    }

    // Clear the whole history table (items are untouched). Emits historyCleared().
    function clearHistory() {
        if (!root.ready) return
        root._write("clearHistory", Db.clearHistorySql(), null)
    }
}
