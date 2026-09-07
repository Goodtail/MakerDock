# MakerWorld integration status

Status for public release 1.6.0, reviewed September 8, 2026.

## Available in the public DMG

- Import and organize local 3MF files, including files the user downloaded manually.
- Consolidate byte-identical imports; reopen archived files through a separate Studio working copy.
- Attach original model/profile page links and open them in an external browser.
- Preserve and display existing source metadata. Prefer already-saved MakerWorld estimates when present.
- Read saved 3MF estimates and ask compatible, separately installed official Studio versions for local calculations.
- Record completion, time, filament, notes, and file moves manually.

## Not enabled in the public DMG

Embedded MakerWorld browsing, page-script injection, automated profile metadata capture, intercepted downloads, remote URL handoff downloads, stored-profile browser reuse, and registration as the Bambu Studio URL handler.

Release builds enforce this at the UI and native ingress boundaries. The public configuration test asserts that blocked remote handoffs make no library imports and that the browser has no injected scripts or loaded page. Development work is retained under `MAKERWORLD_INTEGRATION`; it is not a public service integration offering.

## Chrome companion

A Chrome companion extension is planned. It is not included in this repository's public binary release and is not listed as available in the Chrome Web Store. The intended workflow is to carry the user's model/profile context into the library and reuse already-stored files where permitted. No release date is promised.

## Service and content rights

MakerDock's MIT license covers MakerDock's own code and materials. It does not grant MakerWorld service access, an API agreement, trademark rights, or redistribution rights for downloaded models.

The MakerWorld terms reviewed for this project contain restrictions on automated access and extraction. We have not established authorization for the experimental capture integration, so it is disabled in the public binary. A local-file release boundary does not amount to a legal opinion about every possible use or third-party file.

Bambu Studio's open-source code license also does not grant cloud access. MakerDock does not bundle the Studio application, presets, or network plugin. It does not impersonate the official application's cloud identity.

References: [MakerWorld User Agreement](https://makerworld.com/en/user-agreement), [Bambu's explanation of code licensing and cloud access](https://blog.bambulab.com/setting-the-record-straight-on-cloud-access-and-community/), [third-party notices](../THIRD_PARTY_NOTICES.md).
