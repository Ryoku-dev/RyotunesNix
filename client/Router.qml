pragma Singleton
import QtQuick
import Quickshell

// The page stack: push/pop/replace and a remembered scroll offset per entry, so back-navigation
// lands where you left. The whole array is replaced on each mutation (never patched in place) so
// bindings on `stack`/`current`/`canGoBack` re-run. Entries are { page, params, scrollY }.
Singleton {
    id: root

    property var stack: [{ page: "home", params: ({}), scrollY: 0 }]
    readonly property var current: root.stack.length ? root.stack[root.stack.length - 1] : null
    readonly property bool canGoBack: root.stack.length > 1
    signal navigationRequested()

    function entry(page, params) {
        return { page: page, params: params === undefined ? ({}) : params, scrollY: 0 };
    }

    function push(page, params) {
        var s = root.stack.slice();
        s.push(root.entry(page, params));
        root.stack = s;
        root.navigationRequested();
    }

    function pop() {
        if (root.stack.length <= 1) return;
        var s = root.stack.slice();
        s.pop();
        root.stack = s;
        root.navigationRequested();
    }

    function replace(page, params) {
        var s = root.stack.slice();
        s[s.length - 1] = root.entry(page, params);
        root.stack = s;
        root.navigationRequested();
    }

    // Persist the live scroll position of the current entry (called as a page scrolls) so it can be
    // restored when the user comes back to it.
    function setScroll(y) {
        if (!root.stack.length) return;
        var s = root.stack.slice();
        var top = s[s.length - 1];
        s[s.length - 1] = { page: top.page, params: top.params, scrollY: y };
        root.stack = s;
    }
}
