import QtQuick
import QtQuick.Controls as Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
    id: root
    moduleName: "cynricantao.system-monitor"
    ipcTarget: "cynricantao.system-monitor"
    manageIpc: false
    implicitWidth: barRow.implicitWidth
    implicitHeight: barRow.implicitHeight
    property var data: ({})
    property var details: ({})
    property string sortBy: "memory"
    property string memoryMode: "rss"
    property bool applicationsView: false
    property double receivedAt: 0
    property double clock: Date.now()
    readonly property bool stale: !receivedAt || clock - receivedAt > 8000
    readonly property color ink: bar ? bar.barForeground : Color.foreground
    readonly property color cpuColor: "#7dcfff"
    readonly property color ramColor: "#bb9af7"
    readonly property color gpuColor: "#9ece6a"
    readonly property color warmColor: "#e0af68"
    function tint(c, alpha) { return Qt.rgba(c.r,c.g,c.b,alpha) }
    readonly property string family: bar ? bar.fontFamily : Style.font.family
    readonly property var apps: (details.apps || []).map(function(a) {
        return Object.assign({}, a, {displayMemory:root.memoryMode === "rss" ? a.rss : a.pss})
    }).sort(function(a,b) {
        var av = root.sortBy === "cpu" ? a.cpu : a.displayMemory
        var bv = root.sortBy === "cpu" ? b.cpu : b.displayMemory
        return ((bv === null || bv === undefined ? -1 : bv) - (av === null || av === undefined ? -1 : av)) || a.name.localeCompare(b.name)
    })
    readonly property string backend: Qt.resolvedUrl("backend.py").toString().replace(/^file:\/\//, "")
    function pct(n) { return n === null || n === undefined || stale ? "—" : Math.round(n) + "%" }
    function bytes(n) {
        if (n === undefined || n === null) return "Unavailable"
        var units = ["B", "KiB", "MiB", "GiB", "TiB"]; var i = 0
        while (n >= 1024 && i < 4) { n /= 1024; i++ }
        return n.toFixed(i >= 3 ? 1 : 0) + " " + units[i]
    }
    function val(n, suffix) { return n === null || n === undefined ? "Unavailable" : Number(n).toFixed(1) + suffix }
    function rate(list, key) { return (list || []).reduce(function(a,b) { return a + b[key] }, 0) }
    onOpenedChanged: {
        if (collector.running) collector.write(opened ? "open\n" : "close\n")
        if (!opened) details = ({})
    }
    Timer { interval: 2000; running: true; repeat: true; onTriggered: root.clock = Date.now() }
    Process {
        id: collector
        command: ["/usr/bin/python3", "-I", "-u", root.backend]
        running: true
        stdinEnabled: true
        onStarted: if (root.opened) collector.write("open\n")
        stdout: SplitParser {
            onRead: function(line) {
                try {
                    var result = JSON.parse(line)
                    if (result.error) return
                    root.data = result
                    if (result.detailed) root.details = result
                    root.receivedAt = Date.now()
                    root.clock = root.receivedAt
                } catch (e) { console.warn("System monitor: invalid sampler output") }
            }
        }
    }
    Timer { interval: 10000; running: !collector.running; repeat: true; onTriggered: collector.running = true }
    IpcHandler {
        target: "cynricantao.system-monitor"
        function open(): void { root.open() }
        function close(): void { root.close() }
        function toggle(): void { root.toggle() }

        // Health/UI state only: do not export process names, mounts or counters.
        function status(): string { return JSON.stringify({opened:root.opened, stale:root.stale, sort:root.sortBy, memoryMode:root.memoryMode, view:dashboard.page, allApps:dashboard.allApps, collectorRunning:collector.running}) }
        function memory(name: string): void { root.memoryMode = name === "pss" ? "pss" : "rss" }
        function view(name: string): void { dashboard.page = ["temperatures","storage","network","details"].indexOf(name)>=0 ? name : "processes"; dashboard.allApps = name === "applications" || name === "all"; scroller.contentY=0 }
        function sort(name: string): void { root.sortBy = name === "cpu" ? "cpu" : "memory" }


    }
    Row {
        id: barRow
        parent: root
        anchors.fill: parent
        spacing: Style.space(2)
        Repeater {
            model: [ {key:"memory", icon:"\uefc5", label:"RAM"}, {key:"cpu", icon:"\uf4bc", label:"CPU"}, {key:"gpu", icon:"\uf108", label:"GPU"} ]
            delegate: Item {
                id: metricBar
                required property var modelData
                readonly property var value: modelData.key === "cpu" ? root.data.cpu : (root.data[modelData.key] || {}).percent
                width: Style.space(67)
                height: icon.implicitHeight
                BarIconButton {
                    id: icon
                    width: implicitWidth
                    height: implicitHeight
                    bar: root.bar
                    text: metricBar.modelData.icon
                    useActiveColor: false
                    dimmed: root.stale
                    tooltipText: metricBar.modelData.label + " · " + root.pct(metricBar.value) + " · Click for system dashboard"
                    onPressed: root.toggle()
                }
                WidgetButton {
                    width: implicitWidth
                    height: implicitHeight
                    x: icon.width - Style.space(3)
                    bar: root.bar
                    fixedWidth: Style.space(40)
                    horizontalMargin: 0
                    text: root.pct(metricBar.value)
                    useActiveColor: false
                    fontSize: Style.font.caption
                    tooltipText: icon.tooltipText
                    onPressed: root.toggle()
                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: Style.space(5)
                        anchors.left: parent.left
                        height: Style.space(1)
                        width: parent.width * Math.max(0, Math.min(100, Number(metricBar.value) || 0)) / 100
                        color: metricBar.modelData.key === "cpu" ? root.cpuColor : metricBar.modelData.key === "memory" ? root.ramColor : root.gpuColor; opacity: 0.7
                        Behavior on width { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
                    }
                }
            }
        }
    }
    MonitorPopup {
        id: popup
        borderSpec: Border.surfaceSpec("popups", "border", "#343846", 1)
        anchorItem: barRow
        owner: root
        bar: root.bar
        open: root.opened
        focusTarget: contents
        padding: Style.space(10)
        contentWidth: popup.fittedContentWidth(Style.space(440))
        contentHeight: popup.fittedContentHeight(dashboard.implicitHeight, Math.min(Style.space(460), Math.floor((popup.screen ? popup.screen.height : 1080)*0.44)))
        Item {
            id: contents
            anchors.fill: parent
            Keys.onEscapePressed: root.close()
            Flickable {
                id: scroller
                anchors.fill: parent
                contentHeight: dashboard.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                Controls.ScrollBar.vertical: Controls.ScrollBar {}
                Dashboard {
                    id: dashboard
                    width: parent.width
                    height: implicitHeight
                    monitor: root
                }
            }
        }
    }
}
