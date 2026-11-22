// Renders the Android launcher icons (legacy, adaptive and monochrome) from
// the ship blueprint. Needs Node and Playwright with Chromium:
//   node tool/make_android_icons.js android/app/src/main/res
const { chromium } = require('playwright');
const res = process.argv[2];
const ship = (stroke, accent, fillOpacity, sw, k) => `
    <line x1="30" y1="0" x2="30" y2="100" stroke="${stroke === '#FFFFFF' ? '#FFFFFF' : '#8F9BC0'}" stroke-opacity="0.7" stroke-width="${sw * 0.45 / k}" stroke-dasharray="2 2"/>
    <path d="M30 4 L38 30 L38 52 L54 72 L54 84 L38 78 L36 92 L24 92 L22 78 L6 84 L6 72 L22 52 L22 30 Z" fill="${stroke}" fill-opacity="${fillOpacity}" stroke="${stroke}" stroke-width="${sw / k}"/>
    <path d="M22 30 H38 M22 62 H38 M6 72 L22 66 M54 72 L38 66" fill="none" stroke="${stroke}" stroke-width="${sw * 0.55 / k}"/>
    <circle cx="30" cy="44" r="6" fill="none" stroke="${accent}" stroke-width="${sw / k}"/>
    <circle cx="30" cy="44" r="2" fill="${accent}"/>`;
function svg(size, scale, { background = true, mono = false, rounded = false } = {}) {
  const h = size * scale, w = h * 0.6, x = (size - w) / 2, y = (size - h) / 2;
  const k = h / 100, sw = Math.max(1.4, size / 90);
  const step = size / 8, grid = [];
  for (let i = 1; i < 8; i++) {
    grid.push(`<line x1="${i * step}" y1="0" x2="${i * step}" y2="${size}"/>`);
    grid.push(`<line x1="0" y1="${i * step}" x2="${size}" y2="${i * step}"/>`);
  }
  const bg = background ? `
  <rect width="${size}" height="${size}" rx="${rounded ? size * 0.18 : 0}" fill="#060912"/>
  <g stroke="#6FE3FF" stroke-opacity="0.09" stroke-width="${Math.max(1, size / 256)}">${grid.join('')}</g>
  <circle cx="${size / 2}" cy="${size / 2}" r="${h * 0.56}" fill="none" stroke="#1F2C4A" stroke-width="${sw}"/>` : '';
  const body = mono ? ship('#FFFFFF', '#FFFFFF', 0.25, sw, k) : ship('#5CF2C8', '#B18CFF', 0.12, sw, k);
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 ${size} ${size}">${bg}
  <g transform="translate(${x} ${y}) scale(${k})" stroke-linejoin="round">${body}</g></svg>`;
}
(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ deviceScaleFactor: 1 });
  const densities = { mdpi: 1, hdpi: 1.5, xhdpi: 2, xxhdpi: 3, xxxhdpi: 4 };
  const jobs = [];
  for (const [d, m] of Object.entries(densities)) {
    // Legacy square-ish icon, 48 dp.
    jobs.push([`mipmap-${d}/ic_launcher.png`, Math.round(48 * m), 0.72, { rounded: true }, true]);
    // Adaptive layers, 108 dp; the ship stays inside the 66 dp safe zone.
    jobs.push([`mipmap-${d}/ic_launcher_background.png`, Math.round(108 * m), 0.52, {}, false, true]);
    jobs.push([`mipmap-${d}/ic_launcher_foreground.png`, Math.round(108 * m), 0.52, { background: false }, true]);
    jobs.push([`mipmap-${d}/ic_launcher_monochrome.png`, Math.round(108 * m), 0.52, { background: false, mono: true }, true]);
  }
  for (const [file, size, scale, opts, transparent, bgOnly] of jobs) {
    await page.setViewportSize({ width: size, height: size });
    let markup = svg(size, scale, opts);
    if (bgOnly) markup = markup.replace(/<g transform=[\s\S]*<\/g><\/svg>$/, '</svg>');
    await page.setContent(`<html><body style="margin:0;background:transparent">${markup}</body></html>`);
    await page.screenshot({ path: `${res}/${file}`, clip: { x: 0, y: 0, width: size, height: size }, omitBackground: transparent });
  }
  await browser.close();
})();
