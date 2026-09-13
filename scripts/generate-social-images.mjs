// Render website share cards from real app captures. The font is used only at
// build time; it is not copied to the site or redistributed with the app.
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
const require = createRequire(new URL('../website/package.json', import.meta.url));
const React = require('react');
const sharp = require('sharp');
const { ImageResponse } = require('next/og');
const { content, assetLocale, locales } = await import('../website/src/lib/content.ts');
const { guides } = await import('../website/src/lib/guide.ts');
const root = path.resolve(import.meta.dirname, '../website/public');
const fontPath = process.env.MAKERDOCK_SOCIAL_FONT || '/System/Library/Fonts/Supplemental/Arial Unicode.ttf';
const font = fs.readFileSync(fontPath);
const h = React.createElement;
const data = (file, mime) => `data:${mime};base64,${fs.readFileSync(file).toString('base64')}`;
for (const locale of locales) {
  const c = content[locale], g = guides[locale];
  const screen = 'data:image/png;base64,' + (await sharp(path.join(root, 'screenshots', assetLocale(locale), 'library.webp')).png().toBuffer()).toString('base64');
  const tree = h('div', { style: { display: 'flex', position: 'relative', width: '100%', height: '100%', background: '#fff', color: '#202124', fontFamily: 'Share', overflow: 'hidden' } },
    h('div', { style: { display: 'flex', alignItems: 'center', position: 'absolute', top: 46, left: 54, gap: 14 } },
      h('img', { src: data(path.join(root, 'icon.png'), 'image/png'), width: 54, height: 54 }),
      h('span', { style: { fontSize: 31 } }, 'MakerDock')),
    h('span', { style: { position: 'absolute', right: 54, top: 63, color: '#65676d', fontSize: 19 } }, 'makerdock.goodtail.app'),
    h('div', { style: { position: 'absolute', display: 'flex', flexDirection: 'column', top: 164, left: 54, width: 475, gap: 7, fontSize: locale === 'en' ? 53 : 49, lineHeight: 1.3, letterSpacing: '-1.7px' } },
      h('span', {}, c.hero.line1), h('span', { style: { color: '#245bf5' } }, c.hero.line2)),
    h('span', { style: { position: 'absolute', bottom: 64, left: 54, fontSize: 18, color: '#65676d' } }, g.free),
    h('div', { style: { position: 'absolute', display: 'flex', top: 160, left: 575, width: 860, padding: 12, border: '1px solid #e3e3e7', borderRadius: 22, background: '#f5f5f7' } },
      h('img', { src: screen, width: 834, height: 543, style: { borderRadius: 13 } })),
  );
  const response = new ImageResponse(tree, { width: 1200, height: 630, fonts: [{ name: 'Share', data: font, weight: 400, style: 'normal' }] });
  const output = path.join(root, 'social', assetLocale(locale) + '.png');
  fs.writeFileSync(output, Buffer.from(await response.arrayBuffer()));
  console.log(path.relative(root, output));
}
