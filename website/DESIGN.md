# MakerDock website

## Design read

A Mac utility for people who print in 3D and have lost track of their downloaded files and completed prints. The page should make the library understandable, then offer the Mac download. Real app screenshots are the evidence. No invented testimonials, statistics, or automatic printer tracking claims.

## Direction

Calm, precise, and visibly related to the native app. Design variance 7, motion intensity 4, visual density 3. White and neutral charcoal surfaces with one cobalt accent. Actual screenshot windows are the visual signature, presented at a useful size with an interactive feature tour and accessible enlargement.

Palette: Paper #FFFFFF; Mist #F5F5F7; Ink #202124; Slate #65676D; Cobalt #245BF5. Dark equivalents use neutral #151515 / #202020 / #F5F5F7, never navy. The blue accent brightens in dark mode for contrast.

Type: self-hosted Manrope for Latin display text; native system sans for reading and CJK. Display 44–76 px, section titles 32–48 px, body 16–20 px. Interface corners 10 px; screenshot windows 18 px. Thin borders, broad breathing room, no decorative grids, gradients, or floating badges.

## Layout

```
brand                    tour / questions    language / theme / download

two-line headline                     short explanation + download
                         real library screenshot

problem → concrete benefit         three compact, unequal text columns

feature tour title                  context
vertical feature selector          large, switchable app screenshot

local ownership statement          source + privacy facts

questions                          expandable answers

app icon + final download           macOS compatibility
footer                             source / privacy / Goodtail
```

On mobile the page becomes one column. The feature selector becomes a horizontally scrollable tab row; screenshots open in a keyboard-accessible dialog. No fixed hero height or forced scroll animation. Motion is limited to hover, disclosure, and dialog transitions and respects reduced motion.

## Self-critique

An app icon above centered copy and three equal cards would fit almost any software. Instead, the split headline and action block lead into a full-width library, and the tour uses a working vertical selector. Keep the page anchored to saved 3MF files, plate previews, and print records. Feature claims must match public 0.1.0: manual records, saved estimates, and a planned Chrome companion. MakerWorld automatic capture is not advertised as available.

## Content and assets

English is the default, with Korean, Japanese, and Simplified Chinese routes and corresponding genuine app captures from Docs/screenshots. The six pictured models are original public demo assets. No personal library or login screenshots. Screenshots are optimized without modifying their contents.

## Verification

Production build, TypeScript and lint; desktop/mobile visual inspection; language, theme, tour, dialog and disclosure checks; production Lighthouse audit. Keep the Mac app public version at 0.1.0.
