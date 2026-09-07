# PlateShelf desktop source

SwiftUI + embedded WebKit, macOS 13+, MakerWorld browser and local 3MF library. Main usage guide: `../README.md`. Browser contracts and live verification: `../docs/embedded-browser.md`.

## Build

Install Xcode and XcodeGen. From this folder:

```sh
xcodegen generate
xcodebuild -scheme plateshelf-desktop -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /tmp/PlateShelfBuild \
  CODE_SIGN_IDENTITY=- build
```

Development identity: `PlateShelf-dev` / `com.ninepiece.app.mac.plateshelf.dev` / `AppIconDev`.
Production identity: `PlateShelf` / `com.ninepiece.app.mac.plateshelf` / `AppIcon`.
The app is ad-hoc signed for local execution; Apple portal resources are not required for this command. Configured personal team is `D523TSBMWR`; no company account is used.

## Validation

```sh
(cd Core && swift test)
zsh LinkTests/run.sh
node BrowserTests/bridge.cjs
xcodebuild -scheme plateshelf-desktop -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /tmp/PlateShelfBuild \
  CODE_SIGN_IDENTITY=- test
```

The temporary build location keeps XCTest runtime loads outside protected Documents folders. Tests use their own temporary libraries and never print. App tests cover independent working copies, persistent metadata/source links, queued imports, profile-total provenance, submission/actual-completion distinction, browser URL/context validation and stored-profile reuse with zero transport requests. The bridge harness exercises the bundled page script, including request-time profile changes and the native WebKit message boundary.

All 3MF sources are copied before processing. Core validates ZIP paths, XML, metadata limits and content hashes. The macOS app maintains user-selected folder bookmarks. Printer credentials are not required or collected by PlateShelf.

## Appearance

The library uses a white canvas and cobalt blue (`#2563EB`) actions/selection, with a cool sidebar (`#F7F9FD`) and preview surface (`#F2F5FA`). Light appearance is explicitly applied to the main window and Settings so a system dark appearance does not turn the requested white interface dark. Native typography, layout and actions are unchanged. Named color assets remain the source of truth.
