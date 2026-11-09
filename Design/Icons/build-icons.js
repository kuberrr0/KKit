// Generates KKit's app icon and menu bar icon from the vector sources below.
//
//   npm install playwright && npx playwright install chromium   (once)
//   node Design/Icons/build-icons.js                           (from the repo root)
//
// Writes:
//   Design/Icons/AppIcon.svg, Design/Icons/MenuBarIcon.svg        (masters)
//   App/Assets.xcassets/AppIcon.appiconset/*                      (all macOS sizes)
//   App/Assets.xcassets/MenuBarIcon.imageset/*                    (vector PDF, template)
//
// Concept: "Modular K". The stem and the two arms are separate pieces, like
// KKit's plug-in features.
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const root = path.resolve(__dirname, '../..');
const assets = path.join(root, 'App/Assets.xcassets');

// ---- App icon (1024 x 1024 canvas, 824 pt body per Apple's macOS icon grid) ----

const BODY = 'M100 285a185 185 0 0 1 185-185h454a185 185 0 0 1 185 185v454a185 185 0 0 1-185 185H285a185 185 0 0 1-185-185Z';
const W = 116; // stroke width of the K pieces
const STEM = [360, 300, 360, 724];
const ARM_UP = [512, 438, 664, 300];
const ARM_DOWN = [512, 585, 668, 724];

const line = ([x1, y1, x2, y2], stroke) =>
  `<line x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}" stroke="${stroke}" stroke-width="${W}" stroke-linecap="round"/>`;

// Flat solid colours only: no gradients, glows or shadows.
const COLORS = { body: '#1C1D22', stem: '#FFFFFF', up: '#4D7CFF', down: '#FF6B4A' };

const appIconSVG = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
  <path d="${BODY}" fill="${COLORS.body}"/>
  ${line(STEM, COLORS.stem)}
  ${line(ARM_UP, COLORS.up)}
  ${line(ARM_DOWN, COLORS.down)}
</svg>
`;

// ---- Menu bar icon (18 x 18 pt, black on transparent; macOS tints it as a template) ----

const MB = { width: 2.5, strokes: [[4, 2.6, 4, 15.4], [9.6, 6.9, 14.2, 2.8], [9.6, 11.1, 14.2, 15.2]] };

const menuBarSVG = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 18 18" width="18" height="18">
  <g stroke="#000" stroke-width="${MB.width}" stroke-linecap="round">
${MB.strokes.map(([a, b, c, d]) => `    <line x1="${a}" y1="${b}" x2="${c}" y2="${d}"/>`).join('\n')}
  </g>
</svg>
`;

// A one-page vector PDF with the same strokes (PDF y axis points up).
function menuBarPDF() {
  const ops = [`0 g 0 G ${MB.width} w 1 J`]
    .concat(MB.strokes.map(([a, b, c, d]) => `${a} ${+(18 - b).toFixed(2)} m ${c} ${+(18 - d).toFixed(2)} l S`))
    .join('\n');
  const objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 18 18] /Resources << >> /Contents 4 0 R >>',
    `<< /Length ${Buffer.byteLength(ops)} >>\nstream\n${ops}\nendstream`,
  ];
  let out = '%PDF-1.4\n';
  const offsets = [];
  objects.forEach((body, i) => {
    offsets.push(Buffer.byteLength(out));
    out += `${i + 1} 0 obj\n${body}\nendobj\n`;
  });
  const xref = Buffer.byteLength(out);
  out += `xref\n0 ${objects.length + 1}\n0000000000 65535 f \n`;
  out += offsets.map(o => `${String(o).padStart(10, '0')} 00000 n \n`).join('');
  out += `trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF\n`;
  return out;
}

// ---- Asset catalog ----

const APP_ICON_SIZES = [16, 32, 128, 256, 512]; // points; each at 1x and 2x
const info = { author: 'xcode', version: 1 };
const json = o => JSON.stringify(o, null, 2) + '\n';

(async () => {
  fs.writeFileSync(path.join(__dirname, 'AppIcon.svg'), appIconSVG);
  fs.writeFileSync(path.join(__dirname, 'MenuBarIcon.svg'), menuBarSVG);

  const iconDir = path.join(assets, 'AppIcon.appiconset');
  const menuDir = path.join(assets, 'MenuBarIcon.imageset');
  fs.mkdirSync(iconDir, { recursive: true });
  fs.mkdirSync(menuDir, { recursive: true });
  fs.writeFileSync(path.join(assets, 'Contents.json'), json({ info }));

  const browser = await chromium.launch();
  const images = [];
  for (const pt of APP_ICON_SIZES) {
    for (const scale of [1, 2]) {
      const px = pt * scale;
      const filename = `icon_${pt}x${pt}${scale === 2 ? '@2x' : ''}.png`;
      const page = await browser.newPage({ viewport: { width: px, height: px } });
      const svg = appIconSVG.replace('width="1024" height="1024"', `width="${px}" height="${px}"`);
      await page.setContent(`<html><body style="margin:0">${svg}</body></html>`);
      await page.locator('svg').screenshot({ path: path.join(iconDir, filename), omitBackground: true });
      await page.close();
      images.push({ filename, idiom: 'mac', scale: `${scale}x`, size: `${pt}x${pt}` });
    }
  }
  await browser.close();
  fs.writeFileSync(path.join(iconDir, 'Contents.json'), json({ images, info }));

  fs.writeFileSync(path.join(menuDir, 'MenuBarIcon.pdf'), menuBarPDF());
  fs.writeFileSync(path.join(menuDir, 'Contents.json'), json({
    images: [{ filename: 'MenuBarIcon.pdf', idiom: 'universal' }],
    info,
    properties: { 'preserves-vector-representation': true, 'template-rendering-intent': 'template' },
  }));
  console.log('Icons written to', path.relative(root, assets));
})();
