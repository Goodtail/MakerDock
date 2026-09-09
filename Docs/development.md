# Development

MakerDock is a native SwiftUI/AppKit macOS application with a reusable Swift package in `Core`. All builds include ordinary MakerWorld browsing; automatic download capture is experimental and limited to development builds. `PlateShelf` and `PlateShelfCore` are retained internal module names from before the MakerDock rename.

## Build locally

Install Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen), select Xcode's command-line tools, then run from the repository root:

```sh
xcodegen generate
xcodebuild -scheme makerdock-desktop -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /tmp/MakerDockBuild \
  CODE_SIGN_IDENTITY=- build
open /tmp/MakerDockBuild/Build/Products/Debug/MakerDock-dev.app
```

This uses local ad-hoc signing and does not require Apple portal registration. macOS 13 is the minimum deployment target. ZIPFoundation 0.9.20 is the only external Swift package dependency.

| Configuration | Name | Bundle ID | Icon | Web automation |
| --- | --- | --- | --- | --- |
| Debug | MakerDock-dev | `com.ninepiece.app.mac.makerdock.dev` | Visible DEV badge | Experimental code included |
| Release | MakerDock | `com.ninepiece.app.mac.makerdock` | Production icon | Disabled |

The public Release configuration does not set `MAKERWORLD_INTEGRATION`. Automatic remote imports are rejected before transport, and capture scripts are not injected. MakerWorld and saved source links open inside the app. Studio links explicitly target the separately installed official Bambu Studio. Neither build declares or claims Bambu Studio's schemes. Production uses `makerdock` and the legacy `plateshelf` scheme; development uses `makerdock-dev` and `plateshelf-dev`. On a normal launch, old MakerDock-owned Studio associations are restored to official Studio. See [integration status](integration-status.md).

Put temporary builds in a `.noindex` directory and avoid keeping multiple exported `.app` bundles beside the installed app. Preserve release DMGs for rollback instead. A development build should never become the handler for production links.

The presence of development code is not permission to use a third-party service. Offline tests use fixtures and fake transport; they do not require MakerWorld login or printer access.

## Tests

```sh
(cd Core && swift test)
zsh LinkTests/run.sh
node BrowserTests/bridge.cjs
xcodebuild -scheme makerdock-desktop -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /tmp/MakerDockBuild \
  CODE_SIGN_IDENTITY=- test
```

Validate the public configuration separately:

```sh
xcodebuild -scheme makerdock-desktop -configuration Release \
  -destination 'platform=macOS' -derivedDataPath /tmp/MakerDockReleaseTests \
  CODE_SIGN_IDENTITY=- ENABLE_TESTABILITY=YES ENABLE_HARDENED_RUNTIME=NO \
  ONLY_ACTIVE_ARCH=YES \
  -only-testing:PlateShelfTests/PublicDistributionTests test
```

The last command disables hardened runtime only for the ad-hoc XCTest host so it can load the test frameworks. Distributed archives keep hardened runtime enabled, are signed with Developer ID, and are checked independently. Never distribute a test host.

Tests create temporary libraries and never submit a print. Coverage includes content deduplication, archive safety, working copies, source provenance, estimate priority, legacy record decoding, file-move recovery, bulk operation retries, localization parity, and public-release integration boundaries. Queue tests cover ordering and overrides across restart, completion and trash removal, failed writes, duplicate completion events, available-time planning, unknown durations, and time sorting.

## Data and screenshots

Library data lives under `~/Library/Application Support/<bundle-id>/`. Production and development libraries are separate. An explicit `--library-root` launch argument can point an instance at an isolated test/demo folder without migrating a real library.

See [screenshot reproduction](screenshots/README.md). Original example geometry is generated locally; demo metadata and estimated durations are illustrative rather than measured print results.

## Maintainer release process

See [release instructions](release.md). This project's official signing identity belongs only to **CHANWOO KOO (D523TSBMWR)**. Local contributor builds should use the ad-hoc command above. Never use the separate company account named in `AGENTS.md` for MakerDock resources.

Version and build numbers are in `Config/Version.xcconfig`. Keep a local commit and annotated checkpoint for verified release changes. Preserve user library data during app replacement; a source rollback does not roll back a user's files or print history.
