import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// One bar icon and one panel for everything you serve yourself. The panel is
// strictly a display: bin/servings-probe reads the services file, checks
// every row, and prints a report; this file draws the report. A light per
// row, green when the service answered and red when it did not.
Panel {
  id: root
  moduleName: "lkzwieder.servings"
  ipcTarget: "lkzwieder.servings"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color hoverFill: Style.hoverFillFor(foreground, Color.accent)

  // The theme has an urgent color but no "all good" color, so green ships as a
  // default and both lights can be overridden from shell.json.
  readonly property color upColor: String(setting("upColor", "") || "#7fb069")
  readonly property color downColor: String(setting("downColor", "") || "") !== ""
    ? String(setting("downColor", "")) : urgent
  readonly property color unknownColor: alpha(foreground, 0.30)

  readonly property string home: Quickshell.env("HOME") || ""
  // A third-party plugin lives wherever the user installed it, so resolve the
  // probe relative to this file instead of guessing a path.
  readonly property string pluginDir: {
    var url = String(Qt.resolvedUrl("."))
    var path = url.indexOf("file://") === 0 ? url.slice(7) : url
    return path.charAt(path.length - 1) === "/" ? path.slice(0, -1) : path
  }
  readonly property string configPath: {
    var raw = String(setting("configPath", "") || "").trim()
    if (raw === "") return home + "/.config/omarchy/servings.json"
    if (raw === "~") return home
    if (raw.indexOf("~/") === 0) return home + raw.substring(1)
    if (raw.indexOf("$HOME/") === 0) return home + raw.substring(5)
    return raw
  }
  readonly property int refreshIntervalSec: Math.max(5, Number(setting("refreshIntervalSec", 30)))
  readonly property int timeoutMs: Math.max(100, Number(setting("timeoutMs", 1500)))

  property var report: null
  property bool probing: false
  property bool pendingProbe: false
  property double reportAtMs: 0
  // "updated Ns ago" reads this instead of Date.now() so the footer keeps
  // moving while the panel sits open.
  property double nowMs: Date.now()

  readonly property var groups: report && report.groups ? report.groups : []
  readonly property int upCount: report ? Number(report.up || 0) : 0
  readonly property int downCount: report ? Number(report.down || 0) : 0
  readonly property bool hasReport: !!report && !report.error
  readonly property bool anyDown: hasReport && downCount > 0
  readonly property string configError: report && report.error ? String(report.error) : ""

  readonly property color lightColor: !hasReport ? unknownColor : (anyDown ? downColor : upColor)

  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }

  function statusColor(service) {
    if (!service) return unknownColor
    return service.up ? upColor : downColor
  }

  function summaryText() {
    if (configError === "config-missing") return "No services file"
    if (configError === "config-invalid") return "Services file is invalid"
    if (!hasReport) return probing ? "Checking" : "Waiting for the first check"
    if (upCount + downCount === 0) return "No services configured"
    var text = upCount + " up"
    if (downCount > 0) text += " · " + downCount + " down"
    return text
  }

  function agoText(ms) {
    if (!(ms > 0)) return ""
    var seconds = Math.floor(ms / 1000)
    if (seconds < 5) return "just now"
    if (seconds < 60) return seconds + "s ago"
    var minutes = Math.floor(seconds / 60)
    if (minutes < 60) return minutes + "m ago"
    var hours = Math.floor(minutes / 60)
    return hours + "h " + (minutes % 60) + "m ago"
  }

  function footerText() {
    if (!hasReport) return ""
    var text = "Updated " + agoText(nowMs - reportAtMs)
    if (probing) text += " · checking"
    return text
  }

  function rowTooltip(service) {
    if (!service) return ""
    var parts = []
    if (service.detail) parts.push(String(service.detail))
    parts.push(service.up ? "up" : "down")
    if (service.up && service.latencyMs !== undefined) parts.push(Number(service.latencyMs) + " ms")
    if (service.status) parts.push(String(service.status))
    if (service.error) parts.push(String(service.error))
    if (service.open) parts.push("click to open")
    return parts.join(" · ")
  }

  function openService(service) {
    if (!service || !service.open) return
    Quickshell.execDetached(["xdg-open", String(service.open)])
    root.close()
  }

  function editConfig() {
    Quickshell.execDetached(["xdg-open", root.configPath])
    root.close()
  }

  // ---------------------------------------------------------------- probing

  function refreshNow() {
    if (probe.running) {
      // Collapse requests that land mid-probe into one rerun afterwards.
      pendingProbe = true
      return
    }
    probing = true
    probe.command = ["python3", pluginDir + "/bin/servings-probe",
                     "--config", configPath, "--timeout-ms", String(timeoutMs)]
    probe.running = true
  }

  function applyReport(text) {
    var raw = String(text || "").trim()
    if (raw === "") return
    try {
      var parsed = JSON.parse(raw)
      if (parsed && typeof parsed === "object") {
        report = parsed
        reportAtMs = Date.now()
        nowMs = reportAtMs
      }
    } catch (e) {
      console.warn("lkzwieder.servings", "Ignoring bad report", e)
    }
  }

  Process {
    id: probe
    running: false

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyReport(text)
    }

    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text.trim() !== "") console.warn("lkzwieder.servings", text.trim())
    }

    onExited: {
      root.probing = false
      if (root.pendingProbe) {
        root.pendingProbe = false
        root.refreshNow()
      }
    }
  }

  Timer {
    interval: root.refreshIntervalSec * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshNow()
  }

  Timer {
    interval: 1000
    running: root.opened
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  // The services file is the user's; a save there should show up without
  // waiting out the refresh interval.
  FileView {
    path: root.configPath
    watchChanges: true
    printErrors: false
    onFileChanged: root.refreshNow()
  }

  onOpenedChanged: if (opened) {
    nowMs = Date.now()
    if (panelFlick) panelFlick.contentY = 0
    refreshNow()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refreshNow(); return "ok" }
    // What the panel is showing, for scripts and for checking a headless box.
    function status(): string {
      return JSON.stringify({
        up: root.upCount, down: root.downCount, probing: root.probing,
        error: root.configError, configPath: root.configPath,
        updatedAt: root.reportAtMs > 0 ? new Date(root.reportAtMs).toISOString() : "",
        down_services: root.groups.reduce(function(acc, g) {
          (g.services || []).forEach(function(s) { if (!s.up) acc.push(g.name + " / " + s.name + " (" + s.address + ")") })
          return acc
        }, [])
      })
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    useActiveColor: false
    tooltipText: "Servings · " + root.summaryText()
    iconComponent: Component {
      Item {
        ServingsLogo {
          anchors.centerIn: parent
          iconSize: Style.space(12)
          color: root.barForeground
          dotColor: root.lightColor
        }
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.MiddleButton) root.refreshNow()
      else if (buttonCode === Qt.RightButton) root.editConfig()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onMoveRequested: function(dx, dy) {
        if (dy !== 0)
          panelFlick.contentY = root.clamp(panelFlick.contentY + dy * Style.space(56), 0,
                                           Math.max(0, panelFlick.contentHeight - panelFlick.height))
      }
      onActivateRequested: root.refreshNow()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) { if (t === "r" || t === "R") root.refreshNow() }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          // ---------- Hero: mark · name · summary ----------
          PanelHero {
            width: parent.width
            title: "Servings"
            meta: root.summaryText()
            foreground: root.foreground
            fontFamily: root.fontFamily

            iconComponent: Component {
              ServingsLogo {
                iconSize: Style.font.display
                color: root.foreground
                dotColor: root.lightColor
              }
            }
          }

          // ---------- No file / bad file ----------
          BorderSurface {
            visible: root.configError !== ""
            width: parent.width
            implicitHeight: configText.implicitHeight + Style.spacing.xl * 2
            color: root.alpha(root.urgent, 0.10)
            borderSpec: Border.flat(root.alpha(root.urgent, 0.35), 1)
            radius: Style.cornerRadius

            Text {
              id: configText
              textFormat: Text.PlainText
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(12)
              anchors.rightMargin: Style.space(12)
              text: root.configError === "config-missing"
                ? "Nothing to check yet. Describe your services in\n" + root.configPath
                  + "\n(see services.example.json in the plugin folder)."
                : "Could not read " + root.configPath + "\n"
                  + String(root.report && root.report.errorDetail ? root.report.errorDetail : "")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WrapAnywhere
            }
          }

          Text {
            visible: root.hasReport && root.groups.length === 0
            width: parent.width
            topPadding: Style.space(24)
            text: "The services file has no services in it."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
          }

          // ---------- One section per group ----------
          Repeater {
            model: root.groups

            Column {
              id: groupColumn
              required property var modelData
              width: column.width
              spacing: Style.spacing.md

              readonly property var services: modelData.services || []

              PanelSeparator {
                foreground: root.foreground
              }

              Item {
                width: parent.width
                implicitHeight: groupHeader.implicitHeight

                PanelSectionHeader {
                  id: groupHeader
                  text: String(groupColumn.modelData.name || "").toUpperCase()
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  textFormat: Text.PlainText
                  visible: Number(groupColumn.modelData.down || 0) > 0
                  text: groupColumn.modelData.down + " down"
                  color: root.downColor
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                }
              }

              Repeater {
                model: groupColumn.services

                ServiceRow {
                  required property var modelData
                  width: groupColumn.width
                  service: modelData
                }
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: text !== ""
            width: parent.width
            topPadding: Style.space(2)
            text: root.footerText()
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
          }
        }
      }
    }
  }

  // One service: light, name, address. The row highlights on hover and opens
  // the service in the browser on click when it has somewhere to open.
  component ServiceRow: Item {
    id: row
    property var service: null

    readonly property bool clickable: !!service && String(service.open || "") !== ""

    implicitHeight: Math.max(Style.spacing.popupRowHeight, nameText.implicitHeight + Style.spacing.lg)

    Rectangle {
      anchors.fill: parent
      anchors.leftMargin: -Style.space(6)
      anchors.rightMargin: -Style.space(6)
      radius: Style.cornerRadius
      color: rowHover.containsMouse ? root.hoverFill : "transparent"
    }

    Rectangle {
      id: light
      width: Style.space(8)
      height: Style.space(8)
      radius: width / 2
      color: root.statusColor(row.service)
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter

      Behavior on color {
        ColorAnimation { duration: 200 }
      }
    }

    Text {
      id: nameText
      textFormat: Text.PlainText
      text: row.service ? String(row.service.name || "") : ""
      color: row.service && !row.service.up ? root.downColor : root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
      anchors.left: light.right
      anchors.leftMargin: Style.space(10)
      anchors.right: addressText.left
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      id: addressText
      textFormat: Text.PlainText
      text: row.service ? String(row.service.address || "") : ""
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
    }

    MouseArea {
      id: rowHover
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: row.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
      acceptedButtons: Qt.LeftButton
      onClicked: root.openService(row.service)
    }

    PanelToolTip {
      visible: rowHover.containsMouse
      text: root.rowTooltip(row.service)
      fontFamily: root.fontFamily
    }
  }
}
