# PlateShelf desktop source

SwiftUI, macOS 13+, local 3MF library. Main usage guide: `../README.md`.

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
xcodebuild -scheme plateshelf-desktop -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /tmp/PlateShelfBuild \
  CODE_SIGN_IDENTITY=- test
```

The temporary build location keeps XCTest runtime loads outside protected Documents folders. Tests use their own temporary libraries and never print. App integration tests cover independent working copies, persistent metadata/source links, queued imports, profile-total provenance and submission/actual-completion distinction.

All 3MF sources are copied before processing. Core validates ZIP paths, XML, metadata limits and content hashes. The macOS app maintains user-selected folder bookmarks. Printer credentials are not required or collected by PlateShelf.
