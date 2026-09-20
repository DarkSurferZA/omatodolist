import QtQuick
import Quickshell.Io
import qs.Ui
import "data" as Data

BarWidget {
    id: root
    moduleName: "io.github.darksurferza.omatodolist"

    // Bar.qml's findPanelWidget requires open/close/opened on the bar-widget
    // root (not the nested panel), so the widget is the popout identity.
    readonly property bool opened: panelItem ? panelItem.opened === true : false

    function open() { if (panelItem) panelItem.open() }
    function close() { if (panelItem) panelItem.close() }
    function togglePanel() { if (panelItem) panelItem.toggle() }

    // Forwarded: Bar.requestPopout prefers closeForPopoutSwitch over close,
    // and KeyboardPanel reads popoutSwitchClosing back off its owner.
    readonly property bool popoutSwitchClosing: panelItem ? panelItem.popoutSwitchClosing === true : false
    function closeForPopoutSwitch() { if (panelItem) panelItem.closeForPopoutSwitch() }

    property var panelItem: null

    function injectPanel() {
        var target = panelLoader.item
        if (!target) return
        panelItem = target
        if ("bar" in target) target.bar = root.bar
        if ("settings" in target) target.settings = root.settings
        if ("anchorItem" in target) target.anchorItem = button
        if ("hostWidget" in target) target.hostWidget = root
    }

    // Mutations go through the async sqlite3 Process, so each call acks
    // immediately and the FileView watcher's reload converges the change onto
    // the panels + list() cache afterwards.
    function ipcAdd(type, title, body) {
        var t = String(title || "").trim()
        if (t === "") return JSON.stringify({ ok: false, error: "title is required" })
        db.add(type, t, String(body || ""))
        return JSON.stringify({ ok: true })
    }
    function ipcList(type) {
        var list = db.items || []
        var out = []
        for (var i = 0; i < list.length; ++i) {
            if (String(list[i].type) !== type) continue
            out.push({
                id: Number(list[i].id),
                type: String(list[i].type),
                title: String(list[i].title),
                body: String(list[i].body || ""),
                status: Number(list[i].status)
            })
        }
        return JSON.stringify(out)
    }
    function ipcToggle(id) {
        var n = Number(id)
        var list = db.items || []
        for (var i = 0; i < list.length; ++i) {
            if (Number(list[i].id) === n) {
                db.setStatus(n, Number(list[i].status) === 1 ? 0 : 1)
                return JSON.stringify({ ok: true })
            }
        }
        return JSON.stringify({ ok: false, error: "item not found: " + n })
    }
    function ipcRemove(id) {
        db.deleteItem(Number(id))
        return JSON.stringify({ ok: true })
    }
    function ipcClearHistory() {
        db.clearHistory()
        return JSON.stringify({ ok: true })
    }

    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    onBarChanged: injectPanel()
    onSettingsChanged: injectPanel()

    // Owns sqlite3 access, the db file watcher, and the cached counts the bar
    // badge binds to. The panel keeps its own instance — the db file is the
    // source of truth, and each watcher keeps its view fresh.
    Data.Db {
        id: db
        Component.onCompleted: db.init()
    }

    readonly property int unreadNotes: db.unreadNotes
    readonly property int inProgressTodos: db.inProgressTodos

    Loader {
        id: panelLoader
        active: true
        source: Qt.resolvedUrl("Panel.qml")
        visible: false
        onLoaded: {
            root.injectPanel()
            Qt.callLater(root.injectPanel)
        }
    }

    IpcHandler {
        target: "scratchpad"

        function open(): void { root.open() }
        function close(): void { root.close() }
        function show(): void { root.open() }
        function hide(): void { root.close() }
        function toggle(): void { root.togglePanel() }

        // `delete` is a reserved word, so the per-row delete is exposed as
        // `remove`; every call returns JSON on stdout.
        function ping(): string { return "ok" }
        function addNote(title: string, body: string): string {
            return root.ipcAdd("note", title, body)
        }
        function addTodo(title: string, body: string): string {
            return root.ipcAdd("todo", title, body)
        }
        function listNotes(): string { return root.ipcList("note") }
        function listTodos(): string { return root.ipcList("todo") }
        function toggleTodo(id: int): string { return root.ipcToggle(id) }
        function remove(id: int): string { return root.ipcRemove(id) }
        function clearHistory(): string { return root.ipcClearHistory() }
    }

    BarIconButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        // md-note_text (Nerd Font / Material Design Icons) — notepad with text lines.
        // QML string literals have no \U escape; encode the astral char as its
        // UTF-16 surrogate pair (U+F039E) so it parses to the real code point.
        text: "\uDB80\uDF9E"
        tooltipText: "omatodolist (" + root.unreadNotes + " / " + root.inProgressTodos + ")"

        onPressed: function(b) {
            if (b === Qt.LeftButton) root.togglePanel()
        }
    }
}
