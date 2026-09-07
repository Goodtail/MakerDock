# MakerDock desktop source

SwiftUI + embedded WebKit, macOS 13+, MakerWorld browser and local 3MF library. Main usage guide: `../README.md`. Browser contracts and live verification: `../docs/embedded-browser.md`.

## Build

Install Xcode and XcodeGen. From this folder:

```sh
xcodegen generate
xcodebuild -scheme makerdock-desktop -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /tmp/MakerDockBuild \
  CODE_SIGN_IDENTITY=- build
```

Development identity: `MakerDock-dev` / `com.ninepiece.app.mac.makerdock.dev` / `AppIconDev`.
Production identity: `MakerDock` / `com.ninepiece.app.mac.makerdock` / `AppIcon`.
The app is ad-hoc signed for local execution; Apple portal resources are not required for this command. Configured personal team is `D523TSBMWR`; no company account is used.

## Validation

```sh
(cd Core && swift test)
zsh LinkTests/run.sh
node BrowserTests/bridge.cjs
xcodebuild -scheme makerdock-desktop -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /tmp/MakerDockBuild \
  CODE_SIGN_IDENTITY=- test
```

The temporary build location keeps XCTest runtime loads outside protected Documents folders. Tests use their own temporary libraries and never print. App tests cover independent working copies, persistent metadata/source links, queued imports, profile-total provenance, submission/actual-completion distinction, browser URL/context validation and stored-profile reuse with zero transport requests. The bridge harness exercises the bundled page script, including request-time profile changes and the native WebKit message boundary.

All 3MF sources are copied before processing. Core validates ZIP paths, XML, metadata limits and content hashes. The macOS app maintains user-selected folder bookmarks. Printer credentials are not required or collected by MakerDock.

## Appearance

The library uses a white canvas and cobalt blue (`#2563EB`) actions/selection, with a cool sidebar (`#F7F9FD`) and preview surface (`#F2F5FA`). Light appearance is explicitly applied to the main window and Settings so a system dark appearance does not turn the requested white interface dark. Native typography, layout and actions are unchanged. Named color assets remain the source of truth.

## Print estimates and distribution review

MakerWorld estimates take precedence when available. The inspector also supports per-printer estimates from the installed official Studio CLI using flattened machine/process presets, isolated temporary preferences and file copies. Calculation results are cached separately by file identity and configuration fingerprint. Original archives remain unchanged. See [the current policy and validation report](Docs/app-store-review-2026-09-08.md).

## Print records, batch editing, and localization (1.5.0)

PrintRun now stores optional durationSeconds, durationSource, and filament snapshots. Old records still decode without these fields. 3MF filament slots preserve profile names, material, color, grams, and meters; startup backfill adds metadata without replacing user annotations. Unknown per-plate usage is never treated as a complete model total. Manual records store user-confirmed values separately from source estimates.

Selection mode works in grid and list layouts. Category, favorite, trash, restore, and completion operations report per-item failures. Completion retains the existing recoverable file-move transaction; successful entries are removed before retry. Batch completion only moves managed archives.

App and Core resources include ko/en/ja/zh-Hans catalogs (367 matching keys). Settings provides a persisted language override and system default. User-authored names and notes remain intact. Tests cover legacy decoding, prefill/edit validation, slot mapping, idempotent backfill, batch persistence and partial retries, selection scoping, and localization key/format parity. Official source field reference: https://github.com/bambulab/BambuStudio/blob/master/src/libslic3r/Format/bbs_3mf.cpp (filament type, color, used_g, used_m).
