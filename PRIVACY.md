# Privacy

Applies to the official MakerDock 0.1.2 public DMG.

MakerDock keeps its model library on your Mac. It does not operate an account service, upload the library to a MakerDock server, or include analytics. An optional local printer connection uses a LAN access code that you supply; no Bambu cloud credentials are requested.

## Stored locally

- Copies of imported 3MF files and their extracted previews and metadata.
- Original file locations and access bookmarks for folders you select.
- Categories, tags, favorites, notes, original page links, and print records you save.
- Printer/profile preferences and cached local print-time calculations.
- Print queue order, start/end timestamps, and any confirmed association with a connected printer job.

The library is stored in `~/Library/Application Support/com.ninepiece.app.mac.makerdock/`. The development app uses a separate `.dev` directory. Trash is recoverable inside the library; it is not immediate erasure. Copies outside MakerDock and system backups are managed separately. Removing the app alone does not delete its library.

## Other applications and websites

MakerWorld pages, source links, and My Collections open in the app's WebKit browser. WebKit sends requests to MakerWorld and its site resources and retains cookies and website data, including your sign-in session, locally. MakerDock does not copy credentials or cookies out of WebKit. The My Collections shortcut reads the account navigation link displayed by the website when you request it; it does not fetch your collection contents through a private API. You can also choose to open a page in your system browser. The websites' own policies apply. Opening a model or calculating a time launches the separately installed official Bambu Studio, which has its own behavior and privacy policy. MakerDock gives it a working copy or temporary calculation copy.

Downloads you start in the embedded browser can be archived with their observed public model URL. Explicit Studio links inside the embedded browser download the requested file, retain its source page, and open a working copy in the separately installed official Studio. A small script handles trusted clicks, Command-click tabs, and the public model link visible in a clicked dialog. It does not read cookies, intercept network requests, or read private API responses. Experimental network capture, automated profile metadata extraction, and external remote URL handoff downloads remain disabled in the public DMG.

The browser keeps tab state while the app is running and stores the last visited model page locally. Reopening a page after relaunch does not restore its complete history, forms, or scroll state. Opening a model in Autodesk Fusion exports an STL mesh using a compatible installed Studio and passes it to the separately installed Fusion application. These applications have their own privacy policies.

## Optional local printer connection

If enabled in Settings, MakerDock connects to the private IP address and serial number you enter. The LAN access code is stored in macOS Keychain, separately for development and production. It is not written into the model library or application logs. Local files store the connection address, serial, enabled state, confirmed job association, reported status and timestamps, and observed filament information. MakerDock reads status over a verified TLS connection on the local network and sends no print commands. It does not import cloud print history or measure actual filament consumption. Disconnect disables reconnection; Forget removes the saved connection and Keychain code. Existing print records are preserved. See [printer connection](Docs/printer-connection.md).

## This website

The landing page is hosted on Vercel and has no application analytics or advertising scripts. Your appearance preference is saved in your browser's local storage. Vercel receives ordinary request information needed to serve the site; GitHub serves release downloads and source code under its own policies. Website screenshots contain original demonstration models, not a user's library.

## Support and contributions

Only share models, screenshots, logs, and diagnostic files you are comfortable making public. Remove personal paths, signed download URLs, authentication data, and creator files that you cannot redistribute before filing an issue. No automatic diagnostic upload is performed by MakerDock.
