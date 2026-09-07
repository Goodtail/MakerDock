<p align="center"><img src="assets/brand/icon-master.png" width="96" alt="MakerDock app icon"></p>

<h1 align="center">MakerDock</h1>
<p align="center"><strong>Your 3D prints, remembered.</strong><br>A native macOS companion for your 3MF collection and Bambu Studio.</p>
<p align="center">English · <a href="README.ko.md">한국어</a> · <a href="README.zh-CN.md">简体中文</a> · <a href="README.ja.md">日本語</a></p>
<p align="center"><a href="https://github.com/Goodtail/MakerDock/releases">Downloads</a> · <a href="#why-makerdock">Why MakerDock?</a> · <a href="#coming-next">Roadmap</a> · <a href="Docs/development.md">Build from source</a></p>
<p align="center">macOS 13+ · Apple Silicon & Intel · Free and open source · MIT</p>

![MakerDock model library in English](Docs/screenshots/en/library.png)

## Why MakerDock?

You find a great model, download its 3MF, and open it in Studio. A week later, you download it again because you cannot remember where you saved it. Your Downloads folder keeps growing. Finder cannot tell you which plate is inside, how long the print might take, or whether you already printed it.

**MakerDock gives your downloaded models a home, and your finished prints a history.** Browse previews instead of filenames, reopen the file you already have, and keep the result alongside the model. It works beside the official Bambu Studio; no custom slicer is required.

## From a folder full of files to a useful library

| The everyday frustration | What MakerDock does |
| --- | --- |
| “Where did I save that model?” | A visual grid and compact list, with search, categories, tags, and favorites. |
| “Did I download this already?” | Consolidates byte-identical imports using file hashes, while keeping track of their source locations. Different profiles remain separate. |
| “What is on all these plates?” | Shows every available plate preview in a list. Click one to enlarge it. |
| “How long will it take?” | Reads stored 3MF estimates. Existing saved MakerWorld estimates take priority; optional local calculations use your selected printer in installed Bambu Studio. |
| “Have I actually printed this?” | Completed and not-yet-completed views, with time, filament, and notes for each recorded print. |
| “How do I clean up fifty files?” | Select multiple models in grid or list view to categorize, favorite, mark complete, move to Trash, or restore. |

### See every plate

Inspect the plates together instead of switching a dropdown one by one. Enlarge saved previews to check the contents before opening the project in Studio.

![Enlarged plate preview](Docs/screenshots/en/plates.png)

### Record a print without filling everything out again

Mark a model complete, check the suggested duration, and save. The time is prefilled from the available estimate and remains editable. Record filament type, color, and grams when available, then add a note for next time. Completed archives move into a dedicated folder; the dialog lets you review the applicable file move.

![Print completion with separate duration, filament, and notes](Docs/screenshots/en/print-record.png)

### Organize a whole batch

Enter selection mode and pick several cards. File a batch into a category, mark it complete, or move it to recoverable Trash. Bulk completion keeps each model's own duration and filament suggestions, with an optional shared note.

![Multiple models selected for batch organization](Docs/screenshots/en/selection.png)

## Also included

- **Folder watching and drag and drop.** Import 3MF files individually or scan the folders you choose.
- **Protected archived copies.** Studio opens a separate working copy, so editing does not overwrite MakerDock's stored original.
- **Source links beside the file.** Attach MakerWorld model and print-profile pages; open them in your browser. Previously saved web metadata stays with the library.
- **Your printer settings.** Select a printer, nozzle, and print quality, or import the current selection from official Bambu Studio. Compatible local calculations are cached.
- **Recoverable organization.** Trash preserves categories, notes, and print records for restoration. Deleting a library entry does not delete an external original.
- **Four interface languages.** English, Korean, Japanese, and Simplified Chinese, selectable in Settings.
- **Local storage.** No MakerDock account, analytics, or cloud upload is required for the library.

## Get started

1. Get the DMG from [Releases](https://github.com/Goodtail/MakerDock/releases). The release notes state its signing and notarization status.
2. Drag **MakerDock** into **Applications**. Requires macOS 13 or later; the universal app supports Apple Silicon and Intel.
3. Import a `.3mf` file, drag files into the window, or choose a folder to watch.
4. Browse the model, open it in your separately installed **official Bambu Studio**, and record completion when the print is finished.

Bambu Studio is optional for library browsing and manual records. It is required to slice or use Studio-based time calculations.

## What an estimate means

An unsliced 3MF may contain geometry and settings without a saved print time. Choosing a printer alone cannot produce an accurate duration: slicing is required. MakerDock can ask a compatible installed Bambu Studio to calculate it, using copies and isolated temporary settings. Review the final setup in Studio before printing.

Completion is **recorded by you**. MakerDock does not automatically detect a finished printer job, read live AMS spool inventory, or measure actual filament consumption. Prefilled estimates and filament values should be adjusted if your result differs.

## Coming next

- **Chrome companion extension — coming soon.** A planned browser-to-library handoff for model/profile context and reuse of previously stored downloads.
- **Embedded MakerWorld capture — experimental, not enabled in the public DMG.** The development source includes work on browsing, download capture, and profile reuse. Public distribution of that integration awaits clarification of the service's permitted use.

The current public release focuses on local files. It does not intercept MakerWorld downloads or register itself as Bambu Studio's URL handler. Open-source licensing does not grant rights to third-party services or models. See [integration status](Docs/integration-status.md).

## Development and license

Built with **SwiftUI, AppKit, and a small Swift 3MF library**. ZIPFoundation handles ZIP archives. Production and development builds have separate identities and storage; development builds show a DEV icon badge.

See [development and tests](Docs/development.md), [privacy](PRIVACY.md), [contributing](CONTRIBUTING.md), and [third-party notices](THIRD_PARTY_NOTICES.md).

MakerDock code, documentation, and original example assets are available under the [MIT license](LICENSE). Bambu Studio is a separate AGPL-licensed application and is not bundled. MakerDock is an independent project by Goodtail, not affiliated with or endorsed by Bambu Lab or MakerWorld. Their names and trademarks belong to their respective owners.

<sub>All screenshots are actual MakerDock captures in the indicated language, using original demonstration models and illustrative estimates. No personal library or downloaded creator assets are included. Screenshot reproduction: <a href="Docs/screenshots/README.md">notes and generator</a>.</sub>
