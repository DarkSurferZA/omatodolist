import QtQuick
import Quickshell
import Quickshell.Io
import "Db.js" as Db

// Scratchpad data layer: the single entry point for all database access.
// Views call this component's methods instead of building SQL or touching
// sqlite3 directly. Writes are serialized through one Process (one at a
// time); each read (counts/list/history) uses its own dedicated Process so
// they refresh independently.
QtObject {
    id: root

    // $XDG_DATA_HOME/omarchy, falling back to ~/.local/share/omarchy.
    readonly property string dataDir: {
        var xdg = Quickshell.env("XDG_DATA_HOME")
        if (xdg && String(xdg) !== "") return String(xdg) + "/omarchy"
        return String(Quickshell.env("HOME")) + "/.local/share/omarchy"
    }
    readonly property string dbPath: root.dataDir + "/scratchpad.db"

    property bool ready: false                 // init() completed
    property string lastError: ""

    // Cached rows (populated by reads; the UI binds to these).
    property var items: []                     // list() results
    property var history: []                   // historyList() results
    property int unreadNotes: 0                // notes with status 0
    property int inProgressTodos: 0            // todos with status 0
    property int totalNotes: 0                 // all notes, unfiltered
    property int totalTodos: 0                 // all todos, unfiltered

    // Last list() filter, remembered so load() can re-fetch the same subset
    // after a change.
    property string listFilter: "all"
    property string listQuery: ""
    property bool _listStale: false            // a list() arrived while one was running

    signal itemsUpdated(var items)
    signal countsUpdated()
    signal historyUpdated(var history)
    signal added(int id)
    signal statusChanged(int id, int status)
    signal updated(int id, string title)
    signal typeChanged(int id)
    signal itemDeleted(int id)
    signal historyRowDeleted(int id)
    signal historyCleared()
    signal failed(string message)

    // Central failure path: surfaces in the journal (console.error) so data-layer
    // errors are visible in the shell logs even before the UI handles them.
    function fail(message) {
        root.lastError = message
        console.error("scratchpad db: " + message)
        root.failed(message)
    }

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
            root.totalNotes = c.notes
            root.totalTodos = c.todos
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
            if (root._listStale) {
                Qt.callLater(function() { root.list(root.listFilter, root.listQuery) })
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

    property string _writeKind: ""
    property var _writeArgs: null
    property var _writeQueue: []

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
            Qt.callLater(root._runNextWrite)

            if (exitCode !== 0) {
                var err = String(writeStdout.text || "").trim()
                if (err === "") err = "sqlite3 exited " + exitCode
                root.fail(err)
                if (kind !== "init") postWriteReload.restart()
                return
            }

            if (kind === "init") {
                root.ready = true
                // (Re)bind the watcher now that the file exists, then load.
                dbFile.reload()
                root.load()
            } else {
                if (kind === "add") root.added(Db.parseId(writeStdout.text))
                else if (kind === "setStatus") root.statusChanged(args.id, args.status)
                else if (kind === "update") root.updated(args.id, args.title)
                else if (kind === "convertType") root.typeChanged(args.id)
                else if (kind === "deleteItem") root.itemDeleted(args.id)
                else if (kind === "deleteHistory") root.historyRowDeleted(args.id)
                else if (kind === "clearHistory") root.historyCleared()
                // Belt-and-braces alongside the watcher: refresh shortly in
                // case it misses our own write to the file.
                postWriteReload.restart()
            }
        }
    }

    // One sqlite3 process at a time; later writes wait their turn instead of
    // being dropped.
    function _enqueue(kind, command, args) {
        root._writeQueue.push({ kind: kind, command: command, args: args })
        root._runNextWrite()
    }
    function _runNextWrite() {
        if (root.writeProcess.running || root._writeQueue.length === 0) return
        var next = root._writeQueue.shift()
        root._writeKind = next.kind
        root._writeArgs = next.args
        root.writeProcess.command = next.command
        root.writeProcess.running = true
    }
    function _write(kind, sql, args) {
        root._enqueue(kind, Db.sqliteCommand(root.dbPath, sql, false), args)
    }

    // Watches the db file; any change (external edits or our own writes)
    // triggers a debounced reload. QtObject has no default property, so this
    // is an explicit property (like the Process objects above) rather than an
    // inline child.
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

    // Create the data dir + apply the schema (idempotent). Call once at start.
    function init() {
        if (root.ready || root._writeKind === "init") return
        root._enqueue("init", Db.initCommand(root.dataDir, root.dbPath), null)
    }

    function loadCounts() {
        if (!root.ready || root.countsProcess.running) return
        root.countsProcess.command = Db.sqliteCommand(root.dbPath, Db.countsSql(), true)
        root.countsProcess.running = true
    }

    // Unified list. filterType: "all"|"note"|"todo"; query: title substring.
    function list(filterType, query) {
        root.listFilter = String(filterType || "all")
        root.listQuery = String(query || "")
        if (!root.ready) return
        if (root.listProcess.running) { root._listStale = true; return }
        root._listStale = false
        root.listProcess.command = Db.sqliteCommand(root.dbPath, Db.listSql(filterType, query), true)
        root.listProcess.running = true
    }

    function historyList() {
        if (!root.ready || root.historyProcess.running) return
        root.historyProcess.command = Db.sqliteCommand(root.dbPath, Db.historySql(), true)
        root.historyProcess.running = true
    }

    // Re-fetch everything with the last list() filter (used by the watcher,
    // after writes, and as the reopen safety net).
    function load() {
        root.loadCounts()
        root.list(root.listFilter, root.listQuery)
        root.historyList()
    }

    function add(type, title, body) {
        if (!root.ready) return
        var t = String(title || "").trim()
        if (t === "") {
            root.fail("add: empty title")
            return
        }
        root._write("add", Db.addSql(type === "todo" ? "todo" : "note", t, body), null)
    }

    function setStatus(id, status) {
        if (!root.ready) return
        var s = status === 1 ? 1 : 0
        root._write("setStatus", Db.setStatusSql(id, s), { id: Number(id), status: s })
    }

    // Type is fixed on edit — use convertType() to change it.
    function update(id, title, body) {
        if (!root.ready) return
        var t = String(title || "").trim()
        if (t === "") {
            root.fail("update: empty title")
            return
        }
        root._write("update", Db.updateSql(id, t, body), { id: Number(id), title: t })
    }

    // Emits typeChanged(id).
    function convertType(id) {
        if (!root.ready) return
        root._write("convertType", Db.convertTypeSql(id), { id: Number(id) })
    }

    // Emits itemDeleted(id).
    function deleteItem(id) {
        if (!root.ready) return
        root._write("deleteItem", Db.deleteItemSql(id), { id: Number(id) })
    }

    // Emits historyRowDeleted(id).
    function deleteHistory(id) {
        if (!root.ready) return
        root._write("deleteHistory", Db.deleteHistorySql(id), { id: Number(id) })
    }

    function clearHistory() {
        if (!root.ready) return
        root._write("clearHistory", Db.clearHistorySql(), null)
    }
}
