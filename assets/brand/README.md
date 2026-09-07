# MakerDock identity

Name: MakerDock (메이커독). Development: MakerDock-dev.
Palette: cobalt blue and white; development badge: amber and navy.

`makerdock-artwork.png` and `makerdock-dev-artwork.png` are the original built-in image_gen outputs. `icon-master.png`, `icon-dev.png`, and the `.icns` files are macOS-sized variants. The asset catalogs also contain the in-app sidebar logos. The packaging script applies only the native rounded tile silhouette, transparent padding, and icon sizes.

## Generation prompts

Built-in image_gen was used, not the CLI/API fallback.

Production concept: A premium macOS icon for MakerDock, a 3D-print model library. A bold white isometric cube rests just above two cobalt-blue docking/print plates. Restrained depth, pale blue side face, soft shadow, immaculate edges, compact silhouette readable at 32 pixels. No printer illustration, letters, external logos, glow or extra symbols.

Final production edit: Keep the cube and two dock plates, their shape, color and lighting. Use a full-bleed opaque cobalt-blue square reaching all four corners and edges, without checkerboard, outer margins or tile border. The central symbol occupies about 74% of the canvas width. macOS packaging supplies the rounded silhouette and padding.

Development edit: Preserve the production cube, blue background and dock. Add a large amber-yellow rounded badge at bottom center, with the exact text “DEV” in bold dark navy sans serif, readable at Dock size. Keep the cube visible and the canvas full bleed.
