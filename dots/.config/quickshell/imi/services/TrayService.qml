pragma Singleton

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Services.SystemTray

Singleton {
    id: root

    property bool smartTray: Config.options.tray.filterPassive
    property list<var> itemsInUserList: SystemTray.items.values.filter(i => (Config.options.tray.pinnedItems.includes(i.id) && (!smartTray || i.status !== Status.Passive)))
    property list<var> itemsNotInUserList: SystemTray.items.values.filter(i => (!Config.options.tray.pinnedItems.includes(i.id) && (!smartTray || i.status !== Status.Passive)))

    property bool invertPins: Config.options.tray.invertPinnedItems
    property list<var> pinnedItems: invertPins ? itemsNotInUserList : itemsInUserList
    property list<var> unpinnedItems: invertPins ? itemsInUserList : itemsNotInUserList

    function getTooltipForItem(item) {
        var result = item.tooltipTitle.length > 0 ? item.tooltipTitle
                : (item.title.length > 0 ? item.title : item.id);
        if (item.tooltipDescription.length > 0) result += " • " + item.tooltipDescription;
        if (Config.options.tray.showItemId) result += "\n[" + item.id + "]";
        return result;
    }

    // Pinning
    function pin(itemId) {
        var pins = Config.options.tray.pinnedItems;
        if (pins.includes(itemId)) return;
        // Assign a new array rather than push into the existing one: a QML list
        // property notifies on assignment, and an in-place push emits nothing,
        // so anything bound to pinnedItems would not see the pin until some
        // unrelated change forced a re-evaluation. `unpin` below already does
        // this correctly - the asymmetry was the bug.
        Config.options.tray.pinnedItems = pins.concat([itemId]);
    }
    function unpin(itemId) {
        Config.options.tray.pinnedItems = Config.options.tray.pinnedItems.filter(id => id !== itemId);
    }
    function isPinned(itemId) {
        for (var i = 0; i < root.pinnedItems.length; i++) {
            if (root.pinnedItems[i].id === itemId)
                return true;
        }
        return false;
    }

    function togglePin(itemId) {
        var pins = Config.options.tray.pinnedItems;
        if (pins.includes(itemId)) {
            unpin(itemId)
        } else {
            pin(itemId)
        }
    }

}
