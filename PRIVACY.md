# Privacy

Applies to the official MakerDock 0.1.0 public DMG.

MakerDock keeps its model library on your Mac. It does not operate an account service, upload the library to a MakerDock server, include analytics, or collect printer/cloud credentials.

## Stored locally

- Copies of imported 3MF files and their extracted previews and metadata.
- Original file locations and access bookmarks for folders you select.
- Categories, tags, favorites, notes, original page links, and print records you save.
- Printer/profile preferences and cached local print-time calculations.

The library is stored in `~/Library/Application Support/com.ninepiece.app.mac.makerdock/`. The development app uses a separate `.dev` directory. Trash is recoverable inside the library; it is not immediate erasure. Copies outside MakerDock and system backups are managed separately. Removing the app alone does not delete its library.

## Other applications and websites

MakerWorld pages, source links, and My Collections open in the app's WebKit browser. WebKit sends requests to MakerWorld and its site resources and retains cookies and website data, including your sign-in session, locally. MakerDock does not copy credentials or cookies out of WebKit. The My Collections shortcut reads the account navigation link displayed by the website when you request it; it does not fetch your collection contents through a private API. You can also choose to open a page in your system browser. The websites' own policies apply. Opening a model or calculating a time launches the separately installed official Bambu Studio, which has its own behavior and privacy policy. MakerDock gives it a working copy or temporary calculation copy.

The public DMG disables experimental automatic download capture, model/profile metadata extraction, and remote link handoff downloads. Ordinary website downloads use a save dialog, and Studio links open the separately installed Bambu Studio. MakerDock stores the last visited model page locally to restore browsing.

## Support and contributions

Only share models, screenshots, logs, and diagnostic files you are comfortable making public. Remove personal paths, signed download URLs, authentication data, and creator files that you cannot redistribute before filing an issue. No automatic diagnostic upload is performed by MakerDock.
