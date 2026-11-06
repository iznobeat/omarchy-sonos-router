import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import qs.Commons as Commons

// Sonos Router: send any single app's audio to any AirPlay (Sonos) speaker
// while everything else stays on the default output.
//
// All PipeWire work happens in bin/sonos-router (pactl + jq), which this panel
// polls for a JSON snapshot. Rows hold plain values only, never live PwNode
// objects, so streams appearing and vanishing can't take the shell down.
Panel {
  id: root
  moduleName: "jhgundersen.sonos-router"
  ipcTarget: "jhgundersen.sonos-router"

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  readonly property string helper: String(Qt.resolvedUrl("bin/sonos-router")).replace(/^file:\/\//, "")

  property var outputs: []      // [{ name, label, kind: "default"|"airplay", sonos }]
  property var streams: []      // [{ id, app, title, sink, corked }]
  property string defaultSink: ""
  property bool airplayActive: false
  property bool loaded: false
  property string errorText: ""
  property string pendingSnapshot: ""

  // Keyboard cursor: a stream row, and an output chip within it.
  property int streamIndex: 0
  property int outputIndex: 0
  property bool cursorActive: false

  readonly property int pollMs: Math.max(1000, Number(setting("refreshIntervalSec", 3)) * 1000)

  function clampString(s, max) {
    s = String(s === undefined || s === null ? "" : s)
    return s.length > max ? s.slice(0, max) + "…" : s
  }

  function applySnapshot(raw) {
    var data
    try { data = JSON.parse(raw) } catch (e) { errorText = strings.t("error.helper"); return }
    if (!data || typeof data !== "object") return

    var outs = []
    var srcOuts = Array.isArray(data.outputs) ? data.outputs.slice(0, 32) : []
    for (var i = 0; i < srcOuts.length; i++) {
      var o = srcOuts[i]
      if (!o || typeof o.name !== "string") continue
      outs.push({
        name: o.name,
        label: clampString(o.label || o.name, 40),
        kind: o.kind === "default" ? "default" : "airplay",
        sonos: !!o.sonos
      })
    }

    var strs = []
    var srcStreams = Array.isArray(data.streams) ? data.streams.slice(0, 32) : []
    for (var j = 0; j < srcStreams.length; j++) {
      var s = srcStreams[j]
      if (!s || typeof s.id !== "number") continue
      strs.push({
        id: s.id,
        app: clampString(s.app, 48),
        title: clampString(s.title, 80),
        sink: typeof s.sink === "string" ? s.sink : "",
        corked: !!s.corked
      })
    }

    outputs = outs
    streams = strs
    defaultSink = typeof data.default === "string" ? data.default : ""
    airplayActive = !!data.airplayActive
    errorText = ""
    loaded = true
    clampCursor()
  }

  function refresh() {
    if (listProc.running) return
    listProc.running = true
  }

  function route(stream, output) {
    if (!stream || !output) return
    if (stream.sink === output.name) return
    var cmd = output.kind === "default"
      ? [helper, "reset", String(stream.id)]
      : [helper, "move", String(stream.id), output.name]
    actionProc.command = cmd
    actionProc.running = true
  }

  function resetAll() {
    actionProc.command = [helper, "reset-all"]
    actionProc.running = true
  }

  // The output a stream is on, as a chip index. A stream sitting on some other
  // non-AirPlay device (headphones while laptop is default, say) matches none.
  function outputIndexFor(stream) {
    for (var i = 0; i < outputs.length; i++)
      if (outputs[i].name === stream.sink) return i
    return -1
  }

  function clampCursor() {
    if (streamIndex > streams.length - 1) streamIndex = Math.max(0, streams.length - 1)
    if (outputIndex > outputs.length - 1) outputIndex = Math.max(0, outputs.length - 1)
  }

  function moveCursor(dx, dy) {
    if (!cursorActive) {
      cursorActive = true
      if (streams.length > 0) outputIndex = Math.max(0, outputIndexFor(streams[streamIndex]))
      return
    }
    if (dy !== 0 && streams.length > 0) {
      streamIndex = Math.max(0, Math.min(streams.length - 1, streamIndex + dy))
      outputIndex = Math.max(0, outputIndexFor(streams[streamIndex]))
    }
    if (dx !== 0 && outputs.length > 0)
      outputIndex = Math.max(0, Math.min(outputs.length - 1, outputIndex + dx))
  }

  function activateCursor() {
    if (!cursorActive || streams.length === 0 || outputs.length === 0) return
    route(streams[streamIndex], outputs[outputIndex])
  }

  function outputGlyph(output) {
    if (!output) return ""
    if (output.kind === "default") return "󰌢"   // laptop
    return "󰓃"                                     // speaker
  }

  onOpenedChanged: {
    if (opened) {
      cursorActive = false
      streamIndex = 0
      outputIndex = 0
      refresh()
    }
  }

  Process {
    id: listProc
    command: [root.helper, "list"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.pendingSnapshot = String(text || "")
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var t = String(text || "").trim()
        if (t !== "") root.errorText = root.clampString(t, 160)
      }
    }
    onExited: function(code) {
      if (code === 0 && root.pendingSnapshot !== "") root.applySnapshot(root.pendingSnapshot)
      else if (code !== 0 && root.errorText === "") root.errorText = strings.t("error.helper")
      root.pendingSnapshot = ""
    }
  }

  Process {
    id: actionProc
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var t = String(text || "").trim()
        if (t !== "") root.errorText = root.clampString(t, 160)
      }
    }
    onExited: refreshSoon.restart()
  }

  Timer {
    id: refreshSoon
    interval: 250
    onTriggered: root.refresh()
  }

  // Fast while the panel is open; slow otherwise, just to keep the bar icon's
  // "something is playing on AirPlay" state current.
  Timer {
    interval: root.opened ? 1500 : root.pollMs
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰓃"
    active: root.airplayActive
    tooltipText: root.airplayActive ? strings.t("tooltip.active") : strings.t("tooltip.idle")
    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.resetAll()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight, Style.space(520))

    content: PanelKeyCatcher {
      id: keyCatcher
      implicitHeight: column.implicitHeight
      anchors.fill: parent
      onMoveRequested: function(dx, dy) { root.moveCursor(dx, dy) }
      onActivateRequested: root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.resetAll()
      }

      ScrollView {
        id: scrollArea
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: column.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff

        Column {
          id: column
          width: scrollArea.availableWidth
          spacing: Style.space(14)

          // ---------- Hero ----------
          Item {
            width: parent.width
            implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)

            Text {
              id: heroIcon
              textFormat: Text.PlainText
              text: "󰓃"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.display
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            Column {
              id: heroLabels
              anchors.left: heroIcon.right
              anchors.leftMargin: Style.space(14)
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                textFormat: Text.PlainText
                text: strings.t("title")
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                elide: Text.ElideRight
                width: parent.width
              }

              Text {
                textFormat: Text.PlainText
                text: (root.airplayActive ? strings.t("status.active") : strings.t("status.idle")).toUpperCase()
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
                elide: Text.ElideRight
                width: parent.width
              }
            }
          }

          PanelSeparator { foreground: root.bar.foreground }

          // ---------- Empty / error states ----------
          Text {
            visible: root.errorText !== ""
            width: parent.width
            textFormat: Text.PlainText
            text: root.errorText
            wrapMode: Text.Wrap
            color: root.bar.urgent || root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            visible: root.loaded && root.streams.length === 0
            width: parent.width
            textFormat: Text.PlainText
            text: strings.t("empty.streams")
            wrapMode: Text.Wrap
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
          }

          Text {
            visible: root.loaded && root.outputs.length <= 1
            width: parent.width
            textFormat: Text.PlainText
            text: strings.t("empty.speakers")
            wrapMode: Text.Wrap
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          // ---------- One block per app stream ----------
          Repeater {
            model: root.streams

            Column {
              id: streamBlock
              required property var modelData
              required property int index
              readonly property var stream: modelData
              width: column.width
              spacing: Style.space(6)

              Row {
                width: parent.width
                spacing: Style.space(8)

                Text {
                  textFormat: Text.PlainText
                  text: streamBlock.stream.app
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                  elide: Text.ElideRight
                  width: Math.min(implicitWidth, parent.width * 0.5)
                }

                Text {
                  visible: text !== ""
                  textFormat: Text.PlainText
                  text: streamBlock.stream.title
                  color: Qt.darker(root.bar.foreground, 1.5)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                  width: parent.width * 0.5 - Style.space(8)
                  anchors.baseline: parent.children[0].baseline
                }
              }

              Flow {
                width: parent.width
                spacing: Style.space(6)

                Repeater {
                  model: root.outputs

                  CursorSurface {
                    id: chip
                    required property var modelData
                    required property int index
                    readonly property bool isCurrent: streamBlock.stream.sink === modelData.name
                    hasCursor: root.cursorActive && root.streamIndex === streamBlock.index && root.outputIndex === index
                    current: isCurrent
                    bordered: true
                    foreground: root.bar.foreground
                    width: chipRow.implicitWidth + Style.space(16)
                    height: chipRow.implicitHeight + Style.space(10)

                    Row {
                      id: chipRow
                      anchors.centerIn: parent
                      spacing: Style.space(6)

                      Text {
                        textFormat: Text.PlainText
                        text: root.outputGlyph(chip.modelData)
                        color: root.bar.foreground
                        font.family: root.bar.fontFamily
                        font.pixelSize: Style.font.body
                        anchors.verticalCenter: parent.verticalCenter
                      }

                      Text {
                        textFormat: Text.PlainText
                        text: chip.modelData.kind === "default" ? strings.t("output.local") : chip.modelData.label
                        color: root.bar.foreground
                        font.family: root.bar.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        font.bold: chip.isCurrent
                        anchors.verticalCenter: parent.verticalCenter
                      }
                    }

                    MouseArea {
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onContainsMouseChanged: if (containsMouse) {
                        root.cursorActive = true
                        root.streamIndex = streamBlock.index
                        root.outputIndex = chip.index
                      }
                      onClicked: root.route(streamBlock.stream, chip.modelData)
                    }
                  }
                }
              }
            }
          }

          Text {
            visible: root.streams.length > 0
            width: parent.width
            textFormat: Text.PlainText
            text: strings.t("hint.keys")
            wrapMode: Text.Wrap
            color: Qt.darker(root.bar.foreground, 1.6)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}
