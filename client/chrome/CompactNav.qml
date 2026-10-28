pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Ryoku.Ui.Singletons
import "../"
import "../components"

// Icon-only companion to the existing full Sidebar. Fast, accessible navigation
// while the labelled rail is collapsed, without changing Router or playlists.
Rectangle {
    id: root
    signal expandRequested()

    implicitWidth: Style.sp(14)
    color: Tokens.paper

    Hairline {
        anchors.right: parent.right
        width: 1
        height: parent.height
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: Style.sp(3)
        anchors.bottomMargin: Style.sp(3)
        spacing: Style.sp(2)

        IconButton {
            Layout.alignment: Qt.AlignHCenter
            icon: "sidebar"
            iconSize: Style.fs.lg
            diameter: Style.sp(9)
            tip: "Expand navigation"
            tipBelow: true
            onClicked: root.expandRequested()
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.leftMargin: Style.sp(3)
            Layout.rightMargin: Style.sp(3)
            Layout.topMargin: Style.sp(2)
            Layout.bottomMargin: Style.sp(2)
            Layout.preferredHeight: 1
            color: Tokens.lineSoft
        }

        IconButton {
            Layout.alignment: Qt.AlignHCenter
            icon: "home"
            tip: "Home"
            active: Router.current && Router.current.page === "home"
            onClicked: Router.push("home")
        }
        IconButton {
            Layout.alignment: Qt.AlignHCenter
            icon: "search"
            tip: "Search"
            active: Router.current && Router.current.page === "search"
            onClicked: Router.push("search")
        }
        IconButton {
            Layout.alignment: Qt.AlignHCenter
            icon: "radio"
            tip: "Radio"
            active: Router.current && Router.current.page === "radio"
            onClicked: Router.push("radio")
        }
        IconButton {
            Layout.alignment: Qt.AlignHCenter
            icon: "library"
            tip: "Library"
            active: Router.current && Router.current.page === "library"
            onClicked: Router.push("library", { tab: "songs" })
        }
        IconButton {
            Layout.alignment: Qt.AlignHCenter
            icon: "download"
            tip: "Downloads"
            active: Router.current && Router.current.page === "downloads"
            onClicked: Router.push("downloads")
        }

        Item { Layout.fillHeight: true }

        IconButton {
            Layout.alignment: Qt.AlignHCenter
            icon: "settings"
            tip: "Settings"
            active: Router.current && Router.current.page === "settings"
            onClicked: Router.push("settings")
        }
    }
}
