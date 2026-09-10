# MakerDock 0.1.1 — local build 18

- Add **Open in Fusion** below the Studio button in model details and in the library context menu.
- Prepare STL geometry with the separately installed official Bambu Studio. Open a single model directly; for multiple models, choose which one to edit.
- Reuse converted meshes after checking the source bytes, Studio version and complete cache contents. The archived 3MF, print settings and print history remain unchanged.
- Find the installed Autodesk Fusion app across webdeploy updates and use Autodesk's documented `fusion360` open command to request a separate design. No add-in or file association change is required.
- Explain that the result is a mesh without colors, print settings or the original CAD design history. Include Korean, English, Japanese and Simplified Chinese text.

Conversion runs with isolated Studio preferences and has no slicing or printer command. Tests cover multiple exported models, cache reuse and missing-part recovery, original-file preservation, URL encoding, invalid meshes, localization and narrow layouts.

This is a local update. Public version remains 0.1.1; internal build increases to 18.
