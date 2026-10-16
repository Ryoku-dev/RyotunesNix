pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Ryoku.Ui as RU
import "../"
import "../lib/browse.js" as Browse

// A shelf (spec section 4): a SectionHeading over a horizontally flicking row of MediaCards, gap 16,
// each card revealed with a Ryoku.Ui.Entrance stagger. Fed either a feed `section`
// ({ title, items, moreBrowseId, moreParams }) or explicit `title`/`items`. A section with a
// moreBrowseId routes "See all" into its list page; otherwise the host handles `moreClicked`.
ColumnLayout {
    id: root

    property var section: null
    property string title: (section && section.title) ? section.title : ""
    property var items: (section && section.items) ? section.items : []
    property bool more: !!(section && section.moreBrowseId)
    property string mark: ""
    signal moreClicked()

    spacing: Style.sp(4)

    function seeAll() {
        if (root.section && root.section.moreBrowseId)
            Router.push("list", {
                id: root.section.moreBrowseId,
                title: root.section.title,
                params: root.section.moreParams
            });
        else
            root.moreClicked();
    }

    SectionHeading {
        Layout.fillWidth: true
        title: root.title
        mark: root.mark
        more: root.more
        onMoreClicked: root.seeAll()
    }

    Flickable {
        Layout.fillWidth: true
        implicitHeight: rail.implicitHeight
        contentWidth: rail.implicitWidth
        contentHeight: rail.implicitHeight
        flickableDirection: Flickable.HorizontalFlick
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Row {
            id: rail
            spacing: Style.sp(4)
            Repeater {
                model: root.items
                delegate: Item {
                    id: cell
                    required property var modelData
                    required property int index
                    implicitWidth: entrance.implicitWidth
                    implicitHeight: entrance.implicitHeight
                    RU.Entrance {
                        id: entrance
                        index: cell.index
                        MediaCard {
                            id: card
                            onMenuRequested: (sx, sy) => root.openCardMenu(card, sx, sy)
                            item: cell.modelData
                            cardWidth: Style.cardW
                        }
                    }
                }
            }
        }
    }


    // One menu for every card in this container. A song card gets the track menu; an album, artist
    // or playlist is not a track, so it gets the actions that do mean something for it, run through
    // the card's own logic rather than a second copy of it.
    function openCardMenu(card, sx, sy) {
        if (!card || !card.item)
            return;
        var it = card.item;
        var p = cardMenu.mapFromItem(null, sx, sy);
        if (it.kind === "song") {
            cardMenu.customItems = null;
            cardMenu.song = Browse.asSong(it);
        } else {
            cardMenu.song = null;
            cardMenu.customItems = [
                { icon: "play", label: "Play", danger: false, act: () => card.playNow() },
                { icon: "arrow-right", label: "Open", danger: false, act: () => card.open() },
                { icon: "dashboard", label: "Add to shortcuts", danger: false,
                  act: () => Playback.toast(Personal.addPick(it) ? "Added to shortcuts" : "Already in shortcuts", "success") }
            ];
        }
        cardMenu.openAt(p.x, p.y);
    }

    Menu { id: cardMenu }

}
