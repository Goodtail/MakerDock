# MakerDock website

Next.js landing page and getting-started guide for [MakerDock](https://makerdock.goodtail.app). English is the default, with Korean, Japanese, and Simplified Chinese pages and screenshots.

## Local development

Use Node.js 24. Run `npm ci`, then `npm run dev`. Before release, run `npm run lint`, `npm run typecheck`, and `npm run build`. Preview the production build with `npm run start`.

## Content and SEO

- `src/lib/content.ts` contains landing copy and the public download version.
- `src/lib/guide.ts` contains localized browser copy and usage guides.
- `src/lib/metadata.ts` defines canonical URLs, reciprocal language alternates, and localized social previews.
- `src/app/sitemap.ts` includes all eight canonical pages. Change its date only when page content changes.
- The pages render application/organization/site data and guide breadcrumbs as JSON-LD. No reviews, ratings, or testimonials are fabricated.
- `public/social/` contains 1200 × 630 share cards. Regenerate from the repository root with Node 24: `node scripts/generate-social-images.mjs`. It uses a locally installed CJK-capable TTF font (`MAKERDOCK_SOCIAL_FONT` overrides the default macOS Arial Unicode path); only rendered images are distributed.
- Actual app captures use original demonstration models. See `../Docs/screenshots/README.md` for provenance.

The site has no application analytics or advertising scripts. Appearance preference stays in local storage. Do not add tracking without deciding and documenting its privacy implications.

## Deployment

Existing Vercel project: `makerdock`, scope `blick9s-projects`, root directory `website`, production branch `main`, Node.js 24. Domain: `makerdock.goodtail.app`. Project linkage lives in the repository root's ignored `.vercel` directory; do not create another project.

Publish and verify the GitHub DMG asset before deploying a website version that links to it. Deploy from the linked repository root with `npx vercel --prod --scope blick9s-projects`. Verify all four home pages, guides, redirects, social images, robots, sitemap, and the release download afterward. Search-engine indexing is separate from successful deployment; submit the sitemap in the domain owner's Search Console when access is available.
