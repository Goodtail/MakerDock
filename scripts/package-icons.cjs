// Package image-generated artwork into the native macOS icon silhouette and sizes.
// SHARP_MODULE can point at a supplied runtime; no asset generation happens here.
const fs = require('node:fs');
const path = require('node:path');
const sharp = require(process.env.SHARP_MODULE || 'sharp');
const root = path.resolve(__dirname, '..');
const brand = path.join(root, 'assets/brand');

async function main() {
  for (const [artwork, master, appIcon, imageSet] of [
    ['makerdock-artwork.png', 'icon-master.png', 'AppIcon', 'BrandIcon'],
    ['makerdock-dev-artwork.png', 'icon-dev.png', 'AppIconDev', 'BrandIconDev'],
  ]) {
    // Platform chrome only: a standard 864px rounded tile in a transparent 1024px canvas.
    const mask = Buffer.from('<svg width="864" height="864"><rect width="864" height="864" rx="194" fill="white"/></svg>');
    const tile = await sharp(path.join(brand, artwork)).resize(864, 864)
      .composite([{input: mask, blend: 'dest-in'}]).png().toBuffer();
    const output = path.join(brand, master);
    await sharp({create: {width: 1024, height: 1024, channels: 4, background: '#00000000'}})
      .composite([{input: tile, left: 80, top: 80}]).png().toFile(output);
    const appDir = path.join(root, 'Assets.xcassets', appIcon + '.appiconset');
    const spec = JSON.parse(fs.readFileSync(path.join(appDir, 'Contents.json')));
    for (const item of spec.images) {
      const size = parseInt(item.size, 10) * parseInt(item.scale, 10);
      await sharp(output).resize(size, size).png().toFile(path.join(appDir, item.filename));
    }
    const imageDir = path.join(root, 'Assets.xcassets', imageSet + '.imageset');
    fs.mkdirSync(imageDir, {recursive: true});
    for (const size of [128, 256]) await sharp(output).resize(size, size).png().toFile(path.join(imageDir, `icon-${size}.png`));
    fs.writeFileSync(path.join(imageDir, 'Contents.json'), JSON.stringify({images: [
      {filename: 'icon-128.png', idiom: 'universal', scale: '1x'},
      {filename: 'icon-256.png', idiom: 'universal', scale: '2x'},
    ], info: {author: 'xcode', version: 1}}, null, 2) + '\n');
  }
  const extensionDir = path.join(root, '../chrome-extension/icons');
  fs.mkdirSync(extensionDir, {recursive: true});
  for (const size of [16, 32, 48, 128]) await sharp(path.join(brand, 'icon-master.png')).resize(size, size).png().toFile(path.join(extensionDir, `icon-${size}.png`));
}
main().catch(error => { console.error(error); process.exitCode = 1; });
