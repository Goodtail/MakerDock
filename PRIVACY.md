# Privacy

Applies to the official MakerDock 1.6.0 public DMG.

MakerDock keeps its model library on your Mac. It does not operate an account service, upload the library to a MakerDock server, include analytics, or collect printer/cloud credentials.

## Stored locally

- Copies of imported 3MF files and their extracted previews and metadata.
- Original file locations and access bookmarks for folders you select.
- Categories, tags, favorites, notes, original page links, and print records you save.
- Printer/profile preferences and cached local print-time calculations.

The library is stored in `~/Library/Application Support/com.ninepiece.app.mac.makerdock/`. The development app uses a separate `.dev` directory. Trash is recoverable inside the library; it is not immediate erasure. Copies outside MakerDock and system backups are managed separately. Removing the app alone does not delete its library.

## Other applications and websites

Opening a source link launches your browser; that website's policies apply. Opening a model or calculating a time launches the separately installed official Bambu Studio, which has its own behavior and privacy policy. MakerDock gives it a working copy or temporary calculation copy.

The public DMG disables the experimental embedded browser, download capture, and remote link downloads. A development build that enables the browser can retain WebKit cookies/site data and make requests to third-party sites; this public-release statement does not describe those sites' data handling.

## Support and contributions

Only share models, screenshots, logs, and diagnostic files you are comfortable making public. Remove personal paths, signed download URLs, authentication data, and creator files that you cannot redistribute before filing an issue. No automatic diagnostic upload is performed by MakerDock.
