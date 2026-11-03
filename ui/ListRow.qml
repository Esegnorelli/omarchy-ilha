import QtQuick
import "Motion.js" as Motion

// Linha de lista dos popovers e subpáginas (redes, aparelhos, saídas de som).
// FINAL do Phase 0 (dono: lead).
//
//   ListRow { theme: …; width: 442; icon: "headphones"; label: name; sublabel: …
//             pillText: strings.t("common.connect"); pillStyle: "accent"
//             onClicked: …; onPillClicked: … }
//
// Medidas padrão = linha de rede / Bluetooth (442 x 48, círculo 35, nome
// 15.5/600, raio 10.5). A linha de saída de som usa rowHeight 40.5,
// circleSize 30, circleInset 8, labelSize 14.5, radius 9.5 e trailing "check".
//
// - selected: círculo accent com glifo onAccent; rótulo 600 ink. Sem
//   selected, o rótulo usa labelWeight e ink 90%.
// - iconAccent: círculo accent mesmo sem selected (rede conectada).
// - trailing: "" | "check" (glifo 14 inkMuted a 15 px da direita) | "chevron".
// - pillStyle: "accent" (accentSoft + accentInk) | "neutral" (tinta 10% + ink)
//   | "" (sem pílula). Pílula 25.5 de altura, largura max(66, texto + 24).
// - Hover: raised -> rowHover em 110 ms. Delegado direto de Repeater/ListView
//   funciona (nenhuma propriedade required).
Item {
    id: root

    property Theme theme: null
    property string icon: ""
    property bool iconFilled: false
    property bool iconAccent: false
    property string label: ""
    property string sublabel: ""
    property bool selected: false
    property real rowHeight: 48
    property real circleSize: 35
    property real circleInset: (root.rowHeight - root.circleSize) / 2
    property real iconSize: Math.round(root.circleSize * 0.46)
    property real labelSize: 15.5
    property int labelWeight: 600
    property real sublabelSize: 12
    property real radius: 10.5
    property string trailing: ""
    property string pillText: ""
    property string pillStyle: ""
    property real pillInset: 10.5
    property bool focused: false
    property color fill: root.theme ? root.theme.raised : "transparent"

    readonly property bool hovered: area.containsMouse || pillArea.containsMouse
    readonly property bool circleOn: root.selected || root.iconAccent

    signal clicked()
    signal pillClicked()

    implicitWidth: 442
    implicitHeight: root.rowHeight

    Accessible.role: Accessible.Button
    Accessible.name: root.label
    Accessible.description: root.sublabel

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: root.theme ? (root.hovered ? root.theme.rowHover : root.fill) : "transparent"
        Behavior on color {
            ColorAnimation { duration: root.theme ? root.theme.dur(Motion.FADE.HOVER) : 0 }
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }

    Rectangle {
        id: circle
        width: root.circleSize
        height: root.circleSize
        radius: width / 2
        anchors.left: parent.left
        anchors.leftMargin: root.circleInset
        anchors.verticalCenter: parent.verticalCenter
        visible: root.icon !== ""
        color: root.theme ? (root.circleOn ? root.theme.accent : root.theme.rowIcon) : "transparent"
        Behavior on color {
            ColorAnimation { duration: root.theme ? root.theme.dur(Motion.FADE.HOVER) : 0 }
        }

        Icon {
            anchors.centerIn: parent
            name: root.icon
            size: root.iconSize
            filled: root.iconFilled || root.circleOn
            color: root.theme ? (root.circleOn ? root.theme.onAccent : root.theme.ink) : "white"
        }
    }

    Column {
        id: texts
        anchors.left: parent.left
        anchors.leftMargin: root.icon !== "" ? root.circleInset + root.circleSize + 11.5 : 14
        anchors.right: parent.right
        anchors.rightMargin: (pill.visible ? pill.width + root.pillInset + 10 : 0)
            + (root.trailing !== "" ? 34 : 12)
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1

        IlhaText {
            width: parent.width
            theme: root.theme
            size: root.labelSize
            weight: root.selected ? 600 : root.labelWeight
            color: root.theme ? (root.selected ? root.theme.ink : root.theme.alpha(root.theme.ink, 0.92)) : "white"
            text: root.label
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignLeft
        }
        IlhaText {
            width: parent.width
            theme: root.theme
            size: root.sublabelSize
            weight: 400
            color: root.theme ? root.theme.inkMuted : "gray"
            text: root.sublabel
            visible: root.sublabel !== ""
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignLeft
        }
    }

    Icon {
        anchors.right: parent.right
        anchors.rightMargin: 15 - (14 - 9) / 2
        anchors.verticalCenter: parent.verticalCenter
        visible: root.trailing !== ""
        name: root.trailing === "check" ? "check" : "chevron_right"
        size: 14
        color: root.theme ? root.theme.inkMuted : "gray"
        transform: Scale {
            origin.x: 7
            xScale: (root.trailing === "chevron" && root.theme && root.theme.rtl) ? -1 : 1
        }
    }

    Rectangle {
        id: pill
        visible: root.pillStyle !== "" && root.pillText !== ""
        height: 25.5
        width: Math.max(66, pillMetrics.advanceWidth + 24)
        radius: height / 2
        anchors.right: parent.right
        anchors.rightMargin: root.pillInset + (root.trailing !== "" ? 24 : 0)
        anchors.verticalCenter: parent.verticalCenter
        color: !root.theme ? "transparent"
            : root.pillStyle === "accent" ? (pillArea.containsMouse ? root.theme.mix(root.theme.accentSoft, root.theme.accent, 0.12) : root.theme.accentSoft)
            : (pillArea.containsMouse ? root.theme.alpha(root.theme.ink, 0.16) : root.theme.alpha(root.theme.ink, 0.10))
        Behavior on color {
            ColorAnimation { duration: root.theme ? root.theme.dur(Motion.FADE.HOVER) : 0 }
        }

        IlhaMetrics {
            id: pillMetrics
            theme: root.theme
            size: 12.5
            weight: 600
            text: root.pillText
        }

        IlhaText {
            anchors.centerIn: parent
            theme: root.theme
            size: 12.5
            weight: 600
            color: root.theme ? (root.pillStyle === "accent" ? root.theme.accentInk : root.theme.ink) : "white"
            text: root.pillText
        }

        MouseArea {
            id: pillArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.pillClicked()
        }
    }

    FocusRing {
        theme: root.theme
        shown: root.focused
        itemRadius: root.radius
    }
}
