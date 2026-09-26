import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "kcodedev.urchin"

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property string cliPath: decodeURIComponent(String(Qt.resolvedUrl("bin/urchinctl")).replace("file://", ""))
  property var batteryState: ({ found: false, connected: false, left: null, right: null, levels: [] })
  readonly property bool batteryAvailable: batteryState.connected && typeof batteryState.left === "number"
  readonly property bool splitBatteryAvailable: batteryAvailable && typeof batteryState.right === "number"
  readonly property string batteryTooltip: {
    if (!batteryState.found) return "Urchin keyboard · Bluetooth device not found"
    if (!batteryState.connected) return "Urchin keyboard · Bluetooth disconnected"
    if (!batteryAvailable) return "Urchin keyboard · Battery unavailable"
    var value = "Urchin keyboard · Left " + batteryState.left + "%"
    return splitBatteryAvailable ? value + " · Right " + batteryState.right + "%" : value
  }

  function refreshBattery() {
    if (!batteryProc.running) batteryProc.running = true
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function open() {
    refreshBattery()
    if (panelLoader.item) panelLoader.item.open()
  }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() {
    refreshBattery()
    if (panelLoader.item) panelLoader.item.toggle()
  }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true : false

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

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

  Process {
    id: batteryProc
    command: [root.cliPath, "battery"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          root.batteryState = JSON.parse(String(text || "{}"))
        } catch (exception) {
          root.batteryState = ({ found: false, connected: false, left: null, right: null, levels: [] })
        }
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0)
        root.batteryState = ({ found: false, connected: false, left: null, right: null, levels: [] })
    }
  }

  Timer {
    interval: 60000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshBattery()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰌌"
    slotSize: Style.bar.statusSlot
    tooltipText: root.batteryTooltip

    onPressed: function(mouseButton) {
      if (mouseButton === Qt.MiddleButton) {
        root.refreshBattery()
        if (panelLoader.item) panelLoader.item.refresh()
      }
      else root.togglePanel()
    }
  }
}
