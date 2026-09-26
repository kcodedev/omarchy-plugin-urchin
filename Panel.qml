import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "kcodedev.urchin"
  ipcTarget: "kcodedev.urchin"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color accent: Color.accent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color surface: Color.popups.background
  readonly property color diffAddition: "#8fbc8f"
  readonly property color diffDeletion: bar ? bar.urgent : Color.urgent
  readonly property color diffHunk: accent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string repoPath: String(setting("repoPath", "/home/kob/Repos/zmk-urchin-kcodedev"))
  readonly property string keymapPath: String(setting("keymapPath", "config/urchin.keymap"))
  readonly property string layoutPath: String(setting("layoutPath", "config/urchin.json"))
  readonly property string cliPath: decodeURIComponent(String(Qt.resolvedUrl("bin/urchinctl")).replace("file://", ""))

  property var state: ({ ok: false, layers: [], layout: [], artifacts: [], pairedUrchins: [], errors: [] })
  property int selectedLayer: 0
  property int selectedKey: -1
  property string notice: ""
  property string error: ""
  property string logText: ""
  property string diffText: ""
  property string runningAction: ""
  property bool showBluetoothHelp: false

  readonly property var currentLayer: state.layers && state.layers.length > selectedLayer
    ? state.layers[selectedLayer] : null
  readonly property var currentBindings: currentLayer ? currentLayer.bindings : []
  readonly property bool busy: snapshotProc.running || editProc.running || actionProc.running || diffProc.running
  readonly property bool buildBusy: actionProc.running && runningAction.indexOf("Build") === 0

  function cliArgs(extra) {
    return [cliPath, "--repo", repoPath, "--keymap", keymapPath, "--layout", layoutPath].concat(extra)
  }

  function open() {
    controller.show()
    refresh()
  }

  function refresh() {
    if (snapshotProc.running) return
    error = ""
    snapshotProc.command = cliArgs(["snapshot"])
    snapshotProc.running = true
  }

  function close() {
    controller.hide()
  }

  function chooseLayer(index) {
    selectedLayer = index
    selectedKey = -1
    bindingField.text = ""
  }

  function chooseKey(index) {
    selectedKey = index
    bindingField.text = index >= 0 && index < currentBindings.length ? currentBindings[index] : ""
    bindingField.forceActiveFocus()
    bindingField.selectAll()
  }

  function displayBinding(binding) {
    var value = String(binding || "")
    if (value === "&none") return "—"
    if (value === "&trans") return "▽"
    if (value.indexOf("&kp ") === 0) return value.substring(4)
    if (value.indexOf("&sk ") === 0) return "sticky\n" + value.substring(4)
    if (value.indexOf("&mo ") === 0) return "hold\n" + value.substring(4)
    if (value.indexOf("&sl ") === 0) return "sticky\n" + value.substring(4)
    if (value.indexOf("&qt ") === 0) {
      var parts = value.substring(4).split(/\s+/)
      var held = parts.length > 0 ? parts[0].replace(/^L(?=SHIFT|CTRL|ALT|GUI$)/, "") : "HOLD"
      var tapped = parts.length > 1 ? parts.slice(1).join(" ") : "TAP"
      return held + "\n" + tapped
    }
    return value.replace("&", "")
  }

  function diffHtml(diff) {
    var lines = String(diff || "").split("\n")
    var html = ""
    for (var index = 0; index < lines.length; index++) {
      var line = lines[index]
      var color = root.foreground
      var bold = false

      if (line.indexOf("diff --git ") === 0) {
        color = root.diffHunk
        bold = true
      } else if (line.indexOf("@@") === 0) {
        color = root.diffHunk
        bold = true
      } else if (line.indexOf("+++") === 0 || (line.length > 0 && line[0] === "+")) {
        color = root.diffAddition
      } else if (line.indexOf("---") === 0 || (line.length > 0 && line[0] === "-")) {
        color = root.diffDeletion
      } else if (line.indexOf("index ") === 0) {
        color = root.dim
      }

      var escaped = line.replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/\t/g, "    ")
        .replace(/ /g, "&#160;")
      if (escaped === "") escaped = "&#160;"

      var content = bold ? "<b>" + escaped + "</b>" : escaped
      html += "<font color=\"" + String(color) + "\">" + content + "</font>"
      if (index < lines.length - 1) html += "<br>"
    }
    return html
  }

  function keyX(index) {
    // Thumb row: continue one column inward from each half. The main thirty
    // keys retain the physical coordinates from urchin.json unchanged.
    if (index === 30) return Style.space(217)
    if (index === 31) return Style.space(268)
    if (index === 32) return Style.space(370)
    if (index === 33) return Style.space(421)
    var point = state.layout && state.layout.length > index ? state.layout[index] : null
    return point ? (Number(point.x) + 2.25) * 51 : (index % 10) * 51
  }

  function keyY(index) {
    if (index >= 30) return Style.space(174)
    var point = state.layout && state.layout.length > index ? state.layout[index] : null
    return point ? (Number(point.y) + 0.35) * 49 : Math.floor(index / 10) * 49
  }

  function saveBinding() {
    if (!currentLayer || selectedKey < 0 || editProc.running) return
    notice = ""
    error = ""
    editProc.command = cliArgs([
      "set-binding", "--layer", currentLayer.node,
      "--position", String(selectedKey), "--binding", bindingField.text
    ])
    editProc.running = true
  }

  function runAction(label, args) {
    if (actionProc.running) return
    runningAction = label
    notice = ""
    error = ""
    logText = ""
    actionProc.command = cliArgs(args)
    actionProc.running = true
  }

  function showDiff() {
    if (diffProc.running) return
    diffText = "Loading diff…"
    diffProc.command = cliArgs(["diff"])
    diffProc.running = true
  }

  function appendLog(line) {
    var next = logText + (logText === "" ? "" : "\n") + String(line)
    logText = next.length > 30000 ? next.substring(next.length - 30000) : next
    Qt.callLater(function() { logScroll.contentY = Math.max(0, logScroll.contentHeight - logScroll.height) })
  }

  Process {
    id: snapshotProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var parsed = JSON.parse(String(text || "{}"))
          root.state = parsed
          root.selectedLayer = Math.min(root.selectedLayer, Math.max(0, parsed.layers.length - 1))
          if (parsed.errors && parsed.errors.length) root.error = parsed.errors.join("\n")
        } catch (exception) {
          root.error = "Could not read Urchin state: " + exception
        }
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (String(text || "").trim() !== "") root.error = String(text).trim()
    }
  }

  Process {
    id: editProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var result = JSON.parse(String(text || "{}"))
          root.notice = result.before === result.after ? "Binding was already unchanged" : "Saved " + result.before + " → " + result.after
        } catch (exception) {}
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (String(text || "").trim() !== "") root.error = String(text).trim()
    }
    onExited: function(exitCode) { if (exitCode === 0) root.refresh() }
  }

  Process {
    id: diffProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var result = JSON.parse(String(text || "{}"))
          root.diffText = result.diff || "No uncommitted keymap changes."
        } catch (exception) { root.diffText = "Could not parse diff output." }
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (String(text || "").trim() !== "") root.error = String(text).trim()
    }
  }

  Process {
    id: actionProc
    stdout: SplitParser {
      onRead: function(line) {
        var value = String(line)
        if (value.indexOf("URCHIN_RESULT:") === 0) {
          try {
            var result = JSON.parse(value.substring(14))
            root.notice = root.runningAction + " completed"
          } catch (exception) {}
        } else root.appendLog(value)
      }
    }
    stderr: SplitParser {
      onRead: function(line) { root.appendLog(String(line)) }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.error = root.runningAction + " failed. See the log below."
      if (exitCode === 0 && root.runningAction === "Flash left") root.showBluetoothHelp = true
      root.runningAction = ""
      root.refresh()
    }
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { root.refresh() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(790))
    contentHeight: panel.fittedContentHeight(managerColumn.implicitHeight, Style.space(760))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: bindingField.activeFocus
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        id: managerScroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: managerColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: managerColumn
          width: managerScroll.width
          spacing: Style.space(14)

          Row {
            width: parent.width
            spacing: Style.space(12)

            Column {
              width: parent.width - refreshButton.width - parent.spacing
              spacing: Style.space(3)

              Text {
                text: "URCHIN"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                font.letterSpacing: 2
              }

              Text {
                width: parent.width
                text: root.state.branch
                  ? root.state.branch + (root.state.dirty ? " · uncommitted changes" : " · clean")
                  : root.repoPath
                color: root.state.dirty ? Style.selectedStateColor(root.foreground, root.accent) : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideMiddle
              }
            }

            Button {
              id: refreshButton
              iconText: snapshotProc.running ? "󰑓" : "󰑐"
              tooltipText: "Refresh keyboard state"
              iconSpinning: snapshotProc.running
              enabled: !snapshotProc.running
              onClicked: root.refresh()
            }
          }

          Rectangle {
            width: parent.width
            height: 1
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.14)
          }

          Flickable {
            width: parent.width
            height: Style.space(38)
            contentWidth: layerRow.implicitWidth
            contentHeight: height
            clip: true

            Row {
              id: layerRow
              spacing: Style.space(5)
              Repeater {
                model: root.state.layers || []
                Button {
                  required property int index
                  required property var modelData
                  text: modelData.label
                  selected: index === root.selectedLayer
                  onClicked: root.chooseLayer(index)
                }
              }
            }
          }

          Item {
            id: keyboard
            width: parent.width
            height: Style.space(222)

            Repeater {
              model: root.currentBindings
              Button {
                required property int index
                required property var modelData
                x: root.keyX(index)
                y: root.keyY(index)
                width: Style.space(47)
                height: Style.space(40)
                horizontalPadding: Style.space(2)
                verticalPadding: Style.space(2)
                fontSize: String(modelData).length > 11 ? Style.font.caption : Style.font.bodySmall
                text: root.displayBinding(modelData)
                tooltipText: "Key " + (index + 1) + " · " + modelData
                selected: index === root.selectedKey
                bordered: true
                onClicked: root.chooseKey(index)
              }
            }
          }

          Row {
            width: parent.width
            spacing: Style.space(8)

            TextField {
              id: bindingField
              width: parent.width - saveButton.width - parent.spacing
              placeholderText: root.selectedKey < 0 ? "Select a key to edit its ZMK binding" : "Example: &kp ESC"
              enabled: root.selectedKey >= 0 && !editProc.running
              foreground: root.foreground
              onAccepted: root.saveBinding()
              Keys.onEscapePressed: {
                focus = false
                keyCatcher.forceActiveFocus()
              }
            }

            Button {
              id: saveButton
              text: editProc.running ? "Saving…" : "Save binding"
              enabled: root.selectedKey >= 0 && bindingField.text.trim() !== "" && !editProc.running
              active: enabled
              onClicked: root.saveBinding()
            }
          }

          Text {
            visible: root.notice !== ""
            width: parent.width
            text: root.notice
            color: Style.selectedStateColor(root.foreground, root.accent)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.Wrap
          }

          Text {
            visible: root.error !== ""
            width: parent.width
            text: root.error
            color: bar ? bar.urgent : Color.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.Wrap
          }

          Row {
            width: parent.width
            spacing: Style.space(7)

            Button { text: "Build left"; enabled: !actionProc.running; onClicked: root.runAction("Build left", ["build", "left"]) }
            Button { text: "Build right"; enabled: !actionProc.running; onClicked: root.runAction("Build right", ["build", "right"]) }
            Button { text: "Build both"; enabled: !actionProc.running; onClicked: root.runAction("Build both", ["build", "all"]) }
            Button { text: "Settings reset"; enabled: !actionProc.running; onClicked: root.runAction("Build reset", ["build", "reset"]) }
            Button {
              visible: actionProc.running
              text: "Cancel"
              onClicked: actionProc.running = false
            }
          }

          Row {
            width: parent.width
            spacing: Style.space(7)

            Button {
              text: "Flash left"
              enabled: !actionProc.running
              tooltipText: "Wait for a NICENANO bootloader drive, then flash the latest left firmware"
              onClicked: root.runAction("Flash left", ["flash", "left"])
            }
            Button {
              text: "Flash right"
              enabled: !actionProc.running
              tooltipText: "Wait for a NICENANO bootloader drive, then flash the latest right firmware"
              onClicked: root.runAction("Flash right", ["flash", "right"])
            }
            Button { text: "Show diff"; enabled: !diffProc.running; onClicked: root.showDiff() }
            Button {
              text: "ZMK Studio"
              onClicked: Quickshell.execDetached(["xdg-open", "https://zmk.studio/"])
            }
            Button {
              text: "Open source"
              onClicked: Quickshell.execDetached(["xdg-open", root.repoPath])
            }
          }

          Button {
            text: root.showBluetoothHelp ? "Hide Bluetooth recovery" : "Bluetooth recovery"
            onClicked: root.showBluetoothHelp = !root.showBluetoothHelp
          }

          BorderSurface {
            visible: root.showBluetoothHelp
            width: parent.width
            height: recoveryColumn.implicitHeight + Style.space(20)
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
            borderSpec: Border.controlSpec("normal", root.foreground, root.accent)
            radius: Style.cornerRadius
            padding: Style.space(10)

            Column {
              id: recoveryColumn
              width: parent.width
              spacing: Style.space(8)

              Text {
                width: parent.width
                text: "If Bluetooth loops or media keys stop after a left flash:"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.Wrap
              }
              Text {
                width: parent.width
                text: "1. Unplug the left half from USB. 2. Forget its pairing on this computer. 3. Press both left thumb keys together, then R, to clear the keyboard's active host profile. 4. Pair again in Omarchy Bluetooth."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.Wrap
              }
              Repeater {
                model: root.state.pairedUrchins || []
                Button {
                  required property var modelData
                  text: "Forget " + modelData.name + " on this computer"
                  tooltipText: "Remove only this host's pairing for " + modelData.address
                  enabled: !actionProc.running
                  onClicked: root.runAction("Forget Urchin", ["forget-host", modelData.address])
                }
              }
              Text {
                visible: !root.state.pairedUrchins || root.state.pairedUrchins.length === 0
                width: parent.width
                text: "No paired Urchin is currently saved on this computer."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.Wrap
              }
            }
          }

          Text {
            width: parent.width
            text: root.state.docker && root.state.docker.ready
              ? "Docker " + root.state.docker.detail + " ready · local builds are cached"
              : "Local builds unavailable · " + (root.state.docker ? root.state.docker.detail : "checking Docker")
            color: root.state.docker && root.state.docker.ready ? root.dim : (bar ? bar.urgent : Color.urgent)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.Wrap
          }

          BorderSurface {
            visible: root.logText !== "" || actionProc.running
            width: parent.width
            height: Style.space(150)
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
            borderSpec: Border.controlSpec("normal", root.foreground, root.accent)
            radius: Style.cornerRadius
            padding: Style.space(8)

            Flickable {
              id: logScroll
              anchors.fill: parent
              contentWidth: width
              contentHeight: logLabel.implicitHeight
              clip: true
              boundsBehavior: Flickable.StopAtBounds

              Text {
                id: logLabel
                width: logScroll.width
                text: actionProc.running && root.logText === "" ? root.runningAction + "…" : root.logText
                color: root.foreground
                font.family: "monospace"
                font.pixelSize: Style.font.caption
                wrapMode: Text.WrapAnywhere
              }
            }
          }

          BorderSurface {
            visible: root.diffText !== ""
            width: parent.width
            height: Style.space(190)
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
            borderSpec: Border.controlSpec("normal", root.foreground, root.accent)
            radius: Style.cornerRadius
            padding: Style.space(8)

            Flickable {
              id: diffScroll
              anchors.fill: parent
              contentWidth: Math.max(width, diffLabel.implicitWidth)
              contentHeight: diffLabel.implicitHeight
              clip: true
              boundsBehavior: Flickable.StopAtBounds
              ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
              ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }

              Text {
                id: diffLabel
                text: root.diffHtml(root.diffText)
                textFormat: Text.RichText
                color: root.foreground
                font.family: "monospace"
                font.pixelSize: Style.font.caption
                wrapMode: Text.NoWrap
              }
            }
          }

          Text {
            width: parent.width
            text: "Source-first mode · ZMK Studio runtime changes must be restored before flashed keymap changes take effect."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.Wrap
          }
        }
      }
    }
  }
}
