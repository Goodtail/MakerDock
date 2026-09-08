# MakerDock website

The public Next.js website for [MakerDock](https://makerdock.goodtail.app). English is served at the root, with Korean at /ko, Japanese at /ja, and Simplified Chinese at /zh-CN.

## Run locally

Requires Node.js 24 and npm.

```sh
cd website
npm ci
npm run dev
```

Before committing, run npm run lint, npm run typecheck, and npm run build. The production server can be started with npm start.

## Content

Edit src/lib/content.ts for the four translations. Keep public feature claims consistent with the Mac release. Automatic MakerWorld download capture is disabled in the public app; printer completion records are manual, and the Chrome companion is planned.

The download URL intentionally points to the existing 0.1.0 release. Website changes do not change the Mac app version.

The feature tour, accessible image dialog, and appearance selector are client components. Page content and localized metadata are rendered on the server and prerendered. The site has no analytics, contact form, or third-party font requests. Only the appearance preference is stored in the visitor's browser.

## Images and fonts

public/screenshots contains optimized copies of the actual localized captures in ../Docs/screenshots. They show original public demo models. Images were resized and encoded as WebP without changing their contents. public/og.png is an optimized library screenshot for link previews. No private user library is included.

src/fonts contains the Manrope variable Latin font, distributed under the accompanying SIL Open Font License. Body text and CJK use native system fonts. See DESIGN.md for the visual direction.

## Vercel

- Project: makerdock
- Scope: blick9s-projects, the personal scope that owns goodtail.app
- Repository: Goodtail/MakerDock
- Root directory: website
- Framework: Next.js
- Node.js: 24.x
- Domain: makerdock.goodtail.app
- Production branch: main

Vercel builds from the linked GitHub repository. The root .vercelignore limits CLI uploads to website sources. Preview and production deployments are separate; the requested custom domain points to production.

To roll back the website, promote an earlier successful Vercel deployment or revert the website commit. Mac application files, library data, and existing public releases are independent.
