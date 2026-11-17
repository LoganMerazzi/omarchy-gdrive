import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "logan.gdrive"
  ipcTarget: "logan.gdrive"
  manageIpc: false

  readonly property string home: Quickshell.env("HOME")
  readonly property string gdriveBin: home + "/.local/bin/gdrive"
  readonly property string serviceName: "rclone-gdrive.service"
  readonly property string helperPath: decodeURIComponent(Qt.resolvedUrl("status.py").toString().replace(/^file:\/\//, ""))
  readonly property int refreshIntervalSec: Math.max(5, parseInt(String(setting("refreshIntervalSec", 30)), 10) || 30)

  // Drive state, filled by status.py
  property bool installed: false
  property bool configured: false
  property bool mounted: false
  property string mountDir: home + "/GoogleDrive"
  property double usedBytes: 0
  property double totalBytes: 0
  property bool quotaKnown: false
  property double cacheBytes: 0
  property int pendingUploads: 0
  property var folders: []
  property var starred: []
  property string lastError: ""

  // Optimistic mount state: -1 follows reality, 0/1 while a stop/start settles.
  property int _desired: -1
  readonly property bool active: _desired === -1 ? mounted : (_desired === 1)
  readonly property bool busy: mountProcess.running

  // Keyboard cursor: "setup" | "header" | "starred" | "folders"
  property string focusSection: "header"
  property int rowIndex: 0
  property bool cursorActive: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string driveGlyph: "󰊶"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // ── Actions ────────────────────────────────────────────────────────────

  function refresh() {
    if (statusProcess.running) return
    statusProcess.command = ["python3", "-I", helperPath, "gdrive", mountDir, "20"]
    statusProcess.running = true
  }

  function applyStatus(raw) {
    var s
    try { s = JSON.parse(String(raw || "").trim()) } catch (e) { lastError = "Falha ao ler o status do Drive"; return }
    installed = s.installed === true
    configured = s.configured === true
    mounted = s.mounted === true
    if (_desired !== -1 && mounted === (_desired === 1)) _desired = -1
    mountDir = String(s.mountDir || mountDir)
    usedBytes = Number(s.usedBytes || 0)
    totalBytes = Number(s.totalBytes || 0)
    quotaKnown = s.quotaKnown === true
    cacheBytes = Number(s.cacheBytes || 0)
    pendingUploads = Number(s.pendingUploads || 0)
    folders = Array.isArray(s.folders) ? s.folders : []
    starred = Array.isArray(s.starred) ? s.starred : []
    lastError = ""
    ensureCursor()
  }

  function toggleMount() {
    if (!configured || mountProcess.running) return
    _desired = active ? 0 : 1
    mountProcess.command = ["systemctl", "--user", active ? "stop" : "start", serviceName]
    mountProcess.running = true
  }

  function setup() {
    Quickshell.execDetached(["omarchy-launch-floating-terminal-with-presentation", gdriveBin + " setup"])
    close()
  }

  function openFolder(path) {
    Quickshell.execDetached([gdriveBin, "open", path || mountDir])
    close()
  }

  // Starred folders outside My Drive (shared with me) aren't in the mount.
  function openStarred(folder) {
    if (!folder) return
    if (folder.path) openFolder(String(folder.path))
    else openUrl(folder.webUrl)
  }

  function openUrl(url) {
    if (!url) return
    Qt.openUrlExternally(String(url))
    close()
  }

  function openWeb() {
    openUrl("https://drive.google.com")
  }

  // ── Formatting ─────────────────────────────────────────────────────────

  function formatBytes(bytes) {
    var value = Number(bytes || 0)
    if (!isFinite(value) || value <= 0) return "0 B"
    var units = ["B", "KB", "MB", "GB", "TB"]
    var i = 0
    while (value >= 1024 && i < units.length - 1) { value /= 1024; i++ }
    var decimals = value >= 100 || i === 0 ? 0 : (value >= 10 ? 1 : 2)
    return value.toFixed(decimals).replace(/\.0+$/, "").replace(/(\.\d)0$/, "$1").replace(".", ",") + " " + units[i]
  }

  function starredMeta(folder) {
    if (!folder.path) return "Compartilhado comigo · abre no navegador"
    return folder.location ? folder.location : "Meu Drive"
  }

  function heroMeta() {
    if (busy) return _desired === 1 ? "Montando…" : "Desmontando…"
    if (!active) return "Desmontado"
    if (pendingUploads > 0) return "Enviando " + pendingUploads + (pendingUploads === 1 ? " arquivo…" : " arquivos…")
    return "Montado em " + mountDir.replace(home, "~")
  }

  // ── Keyboard cursor ────────────────────────────────────────────────────

  function sectionLength(section) {
    if (section === "starred") return starred.length
    if (section === "folders") return folders.length
    return 1
  }

  function sections() {
    if (!configured) return ["setup"]
    var list = ["header"]
    if (starred.length > 0) list.push("starred")
    if (folders.length > 0) list.push("folders")
    return list
  }

  function ensureCursor() {
    var list = sections()
    if (list.indexOf(focusSection) === -1) { focusSection = list[0]; rowIndex = 0 }
    rowIndex = Math.max(0, Math.min(rowIndex, sectionLength(focusSection) - 1))
  }

  function moveCursor(dy) {
    cursorActive = true
    ensureCursor()
    if (dy === 0) return
    var list = sections()
    var s = list.indexOf(focusSection)
    var next = rowIndex + dy
    if (next < 0 && s > 0) {
      focusSection = list[s - 1]
      rowIndex = sectionLength(focusSection) - 1
    } else if (next >= sectionLength(focusSection) && s < list.length - 1) {
      focusSection = list[s + 1]
      rowIndex = 0
    } else {
      rowIndex = Math.max(0, Math.min(sectionLength(focusSection) - 1, next))
    }
    scrollCursorIntoView()
  }

  function setCursor(section, index) {
    cursorActive = true
    focusSection = section
    rowIndex = index
  }

  function activateCursor() {
    ensureCursor()
    if (focusSection === "setup") setup()
    else if (focusSection === "header") toggleMount()
    else if (focusSection === "starred") openStarred(starred[rowIndex])
    else if (focusSection === "folders") openFolder(folders[rowIndex].path)
  }

  function scrollCursorIntoView() {
    var column = focusSection === "starred" ? starredColumn : (focusSection === "folders" ? folderColumn : null)
    if (focusSection === "header") { panelFlick.contentY = 0; return }
    if (!column || rowIndex >= column.children.length) return
    var item = column.children[rowIndex]
    Qt.callLater(function() {
      if (!item) return
      var margin = Style.space(6)
      var top = item.mapToItem(panelFlick.contentItem, 0, 0).y
      var bottom = top + item.height
      var maxY = Math.max(0, panelFlick.contentHeight - panelFlick.height)
      if (top < panelFlick.contentY + margin) panelFlick.contentY = Math.max(0, top - margin)
      else if (bottom > panelFlick.contentY + panelFlick.height - margin)
        panelFlick.contentY = Math.min(maxY, bottom + margin - panelFlick.height)
    })
  }

  onOpenedChanged: if (opened) {
    cursorActive = false
    panelFlick.contentY = 0
    refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  // ── Processes / timers ─────────────────────────────────────────────────

  Process {
    id: statusProcess
    running: false
    stdout: StdioCollector { id: statusOut; waitForEnd: true }
    stderr: StdioCollector { id: statusErr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) root.applyStatus(statusOut.text)
      else root.lastError = String(statusErr.text || "Falha ao ler o status do Drive").trim().slice(-140)
    }
  }

  Process {
    id: mountProcess
    running: false
    stderr: StdioCollector { id: mountErr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root._desired = -1
        root.lastError = String(mountErr.text || "Falha ao montar o Drive").trim().slice(-140)
      }
      settleTimer.ticks = 0
      settleTimer.restart()
    }
  }

  Timer {
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    // rclone takes a moment to (un)mount; re-poll a few times, then stop overriding.
    id: settleTimer
    property int ticks: 0
    interval: 1000
    repeat: true
    onTriggered: {
      ticks += 1
      root.refresh()
      if (ticks >= 6) { running = false; root._desired = -1 }
    }
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refresh(); return "ok" }
    function toggleMount(): string { root.toggleMount(); return "ok" }
  }

  // ── Bar button ─────────────────────────────────────────────────────────

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.pendingUploads > 0 ? "󰕒" : root.driveGlyph
    opacity: root.active ? 1.0 : 0.5
    tooltipText: root.opened ? "" : "Google Drive · " + root.heroMeta()
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.openFolder(root.mountDir)
      else if (buttonCode === Qt.MiddleButton) root.toggleMount()
      else root.toggle()
    }
  }

  // ── Popup ──────────────────────────────────────────────────────────────

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(600))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; root.ensureCursor(); return }
        root.moveCursor(dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        var k = t.toLowerCase()
        if (k === "r") root.refresh()
        else if (k === "m") root.toggleMount()
        else if (k === "o") root.openFolder(root.mountDir)
        else if (k === "w") root.openWeb()
      }

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

          Item {
            id: header
            visible: root.configured
            width: parent.width
            implicitHeight: hero.implicitHeight
            readonly property bool ringVisible: root.cursorActive && root.focusSection === "header"
            function focusHero() { root.setCursor("header", 0) }

            PanelHero {
              id: hero
              width: parent.width
              title: "Google Drive"
              meta: root.heroMeta()
              foreground: root.foreground
              fontFamily: root.fontFamily
              iconOpacity: root.active ? 1.0 : 0.5
              iconComponent: Component {
                Text {
                  text: root.driveGlyph
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.display
                }
              }
              trailingControl: Component {
                ToggleSwitch {
                  id: mountSwitch
                  checked: root.active
                  busy: root.busy
                  hasCursor: header.ringVisible
                  foreground: hero.foreground
                  onHovered: function(on) { if (on) header.focusHero() }
                  onToggled: root.toggleMount()

                  PanelToolTip {
                    visible: mountSwitch.containsMouse
                    text: root.active ? "Desmontar" : "Montar"
                    fontFamily: hero.fontFamily
                  }
                }
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: root.lastError !== ""
            width: parent.width
            text: root.lastError
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          ActionRow {
            visible: !root.configured
            width: parent.width
            section: "setup"
            rowIdx: 0
            glyph: "󰌋"
            title: root.installed ? "Conectar ao Google Drive" : "Instalar e conectar o Google Drive"
            subtitle: "Abre um terminal para autorizar sua conta"
            onActivated: root.setup()
          }

          Column {
            visible: root.configured
            width: parent.width
            spacing: Style.spacing.labelGap

            InfoPair {
              label: "Armazenamento"
              value: root.quotaKnown ? root.formatBytes(root.usedBytes) + " de " + root.formatBytes(root.totalBytes) : root.formatBytes(root.usedBytes)
            }
            InfoPair { label: "Cache local"; value: root.formatBytes(root.cacheBytes) }
          }

          Row {
            visible: root.configured
            spacing: Style.space(6)

            PanelActionButton {
              iconText: "󰉋"
              tooltipText: "Abrir pasta (o)"
              foreground: root.foreground
              fontFamily: root.fontFamily
              bordered: true
              onClicked: root.openFolder(root.mountDir)
            }
            PanelActionButton {
              iconText: "󰖟"
              tooltipText: "Abrir no navegador (w)"
              foreground: root.foreground
              fontFamily: root.fontFamily
              bordered: true
              onClicked: root.openWeb()
            }
            PanelActionButton {
              iconText: "󰑐"
              tooltipText: "Atualizar (r)"
              foreground: root.foreground
              fontFamily: root.fontFamily
              bordered: true
              enabled: !statusProcess.running
              onClicked: root.refresh()
            }
          }

          PanelSeparator {
            visible: root.configured && root.starred.length > 0
            foreground: root.foreground
          }

          Column {
            visible: root.configured && root.starred.length > 0
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "COM ESTRELA"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Column {
              id: starredColumn
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: root.starred
                ActionRow {
                  required property var modelData
                  required property int index
                  width: starredColumn.width
                  section: "starred"
                  rowIdx: index
                  glyph: "󰚝"
                  title: modelData.name
                  subtitle: root.starredMeta(modelData)
                  trailingGlyph: modelData.path && modelData.webUrl ? "󰖟" : ""
                  trailingTip: "Abrir no navegador"
                  onActivated: root.openStarred(modelData)
                  onTrailingActivated: root.openUrl(modelData.webUrl)
                }
              }
            }
          }

          PanelSeparator {
            visible: root.configured && root.folders.length > 0
            foreground: root.foreground
          }

          Column {
            visible: root.configured && root.folders.length > 0
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "PASTAS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Column {
              id: folderColumn
              width: parent.width
              spacing: Style.space(2)

              Repeater {
                model: root.folders
                ActionRow {
                  required property var modelData
                  required property int index
                  width: folderColumn.width
                  section: "folders"
                  rowIdx: index
                  glyph: "󰉋"
                  title: modelData.name
                  onActivated: root.openFolder(modelData.path)
                }
              }
            }
          }
        }
      }
    }
  }

  // ── Components ─────────────────────────────────────────────────────────

  component ActionRow: CursorSurface {
    id: row
    property string section: ""
    property int rowIdx: 0
    property string glyph: ""
    property string title: ""
    property string subtitle: ""
    property string trailingGlyph: ""
    property string trailingTip: ""
    signal activated()
    signal trailingActivated()

    hasCursor: root.cursorActive && root.focusSection === section && root.rowIndex === rowIdx
    foreground: root.foreground
    implicitHeight: rowContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.setCursor(row.section, row.rowIdx)
      onClicked: row.activated()
    }

    RowLayout {
      id: rowContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Text {
        textFormat: Text.PlainText
        text: row.glyph
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: row.title
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          textFormat: Text.PlainText
          visible: row.subtitle !== ""
          Layout.fillWidth: true
          text: row.subtitle
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      PanelActionButton {
        visible: row.trailingGlyph !== ""
        iconText: row.trailingGlyph
        tooltipText: row.trailingTip
        foreground: root.foreground
        fontFamily: root.fontFamily
        Layout.alignment: Qt.AlignVCenter
        onClicked: row.trailingActivated()
      }
    }
  }

  component InfoPair: Row {
    property string label: ""
    property string value: ""

    width: parent.width
    spacing: Style.space(8)

    Text {
      textFormat: Text.PlainText
      text: label
      color: root.foreground
      opacity: 0.6
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
    Item { width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth - parent.spacing * 2); height: 1 }
    Text {
      textFormat: Text.PlainText
      text: value
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }
}
