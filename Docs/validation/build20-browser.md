# MakerDock 0.1.1 (20): browser interactions

Starting checkpoint: d7343ff, clean working tree. Public version remains 0.1.1.

## Changes

- Tabs use equal widths between 104 and 194 points, then scroll horizontally when they no longer fit. No scroll indicator is drawn. Vertical mouse wheels, horizontal trackpads, and arrow buttons move the strip. The selected tab is revealed on selection and resize. An all-tabs menu exposes full page titles.
- Window-scoped keyboard handling supports tab numbers, cycling, close/reopen, address selection, reload, history, page find and zoom. The window association survives the interval between selecting a tab and attaching its webview, preventing rapid Command-W from closing the window.
- A native context-menu action opens MakerWorld links in background tabs. Public NSView menu hooks and a point-specific DOM link lookup preserve WebKit's image, copy, and editing actions. No private WebKit API is used.
- New labels are available in English, Korean, Japanese, and Simplified Chinese.

## Verification

- Debug: 92 tests passed. Release: 92 tests, one existing development-only test skipped, zero failures. JavaScript navigation and bridge fixtures passed.

- Regression tests cover 24 tabs, numeric selection and wraparound, import protection, rapid switch/close before view attachment, modifier exclusions, width allocation, clamping, wheel input and resizing.
- Local WebKit fixtures verify context-menu insertion, exact URL/background routing, original menu preservation, non-link behavior, blocked URL schemes/download links, text finding, missing matches and zoom limits.
- Native UI checks use a separate empty library. Verified Command-L selection, Command-F typing, Escape, zoom/reset, background right-click opening, equal widths with 10 tabs, and wheel overflow with 15 tabs. Verified tab cycling, Command-W retaining the window, Shift-Command-T restoring the tab, and the all-tabs menu. Existing production library data is not used as a test fixture.

App signing, installation, notarization, and final suite results are recorded with the local build artifact. No public release is created by this change.
