import { readFileSync, writeFileSync, mkdirSync, statSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';

const dir = dirname(fileURLToPath(import.meta.url));
const repo = join(dir, '../..');
const blue = '#0A59F7';
const ink = '#13243C';
const muted = '#617087';
const font = 'HarmonyOS Sans SC, PingFang SC, Noto Sans CJK SC, sans-serif';
const numFont = 'HarmonyOS Sans Condensed, DIN Condensed, Arial Narrow, sans-serif';
const png = (file) => 'data:image/png;base64,' + readFileSync(file).toString('base64');
const logo = png(join(repo, 'entry/src/main/resources/base/media/appicon.png'));
const google = png(join(repo, 'entry/src/main/resources/base/media/issuer_google.png'));
const discord = png(join(repo, 'entry/src/main/resources/base/media/issuer_discord.png'));
const esc = (s) => String(s).replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('"', '&quot;');
const text = (x, y, value, size = 32, weight = 400, color = ink, extra = '') =>
  '<text x="' + x + '" y="' + y + '" font-size="' + size + '" font-weight="' + weight + '" fill="' + color + '" ' + extra + '>' + esc(value) + '</text>';
const rect = (x, y, w, h, r = 0, fill = '#FFFFFF', extra = '') =>
  '<rect x="' + x + '" y="' + y + '" width="' + w + '" height="' + h + '" rx="' + r + '" fill="' + fill + '" ' + extra + '/>';
const img = (href, x, y, w, h, extra = '') =>
  '<image x="' + x + '" y="' + y + '" width="' + w + '" height="' + h + '" href="' + href + '" ' + extra + '/>';
const line = (x1, y1, x2, y2, color = '#DCE4EF', width = 2) =>
  '<line x1="' + x1 + '" y1="' + y1 + '" x2="' + x2 + '" y2="' + y2 + '" stroke="' + color + '" stroke-width="' + width + '"/>';
const group = (id, content, extra = '') => '<g id="' + id + '" ' + extra + '>\n' + content + '\n</g>';
const defs = '<defs>\n' +
  '<linearGradient id="paper" x1="0" y1="0" x2="0.8" y2="1"><stop stop-color="#FCFDFF"/><stop offset="0.5" stop-color="#F4F7FC"/><stop offset="1" stop-color="#EDF3FC"/></linearGradient>\n' +
  '<linearGradient id="glass" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#FFFFFF" stop-opacity="0.98"/><stop offset="1" stop-color="#FAFCFF" stop-opacity="0.92"/></linearGradient>\n' +
  '<linearGradient id="fadeArt" x1="0" y1="0" x2="0" y2="1"><stop stop-color="white" stop-opacity="0"/><stop offset="0.08" stop-color="white"/><stop offset="0.86" stop-color="white"/><stop offset="1" stop-color="white" stop-opacity="0"/></linearGradient>\n' +
  '<mask id="artMask" maskContentUnits="objectBoundingBox"><rect width="1" height="1" fill="url(#fadeArt)"/></mask>\n' +
  '<filter id="shadow" x="-30%" y="-30%" width="160%" height="180%"><feGaussianBlur in="SourceAlpha" stdDeviation="22"/><feOffset dy="20"/><feColorMatrix type="matrix" values="0 0 0 0 0.12 0 0 0 0 0.25 0 0 0 0 0.48 0 0 0 0.15 0"/><feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge></filter>\n' +
  '<filter id="softShadow" x="-25%" y="-25%" width="150%" height="170%"><feGaussianBlur in="SourceAlpha" stdDeviation="12"/><feOffset dy="10"/><feColorMatrix type="matrix" values="0 0 0 0 0.12 0 0 0 0 0.25 0 0 0 0 0.48 0 0 0 0.1 0"/><feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge></filter>\n' +
  '</defs>';

function icon(name, x, y, size = 32, color = ink) {
  const paths = {
    search: '<circle cx="10" cy="10" r="7"/><path d="m15.3 15.3 6.2 6.2"/>',
    plus: '<path d="M12 3v18M3 12h18"/>',
    more: '<circle cx="5" cy="5" r="1.5"/><circle cx="19" cy="5" r="1.5"/><circle cx="5" cy="19" r="1.5"/><circle cx="19" cy="19" r="1.5"/>',
    check: '<path d="m4 12 5 5L20 6"/>',
    arrow: '<path d="M3 12h18m-7-7 7 7-7 7"/>',
    cloud: '<path d="M6 19a5 5 0 0 1-1-10 7 7 0 0 1 13-2 6 6 0 0 1 0 12Z"/>',
    file: '<path d="M6 2h8l5 5v15H6ZM14 2v6h5M9 13h7M9 17h5"/>',
    lock: '<rect x="5" y="10" width="14" height="12" rx="3"/><path d="M8 10V6a4 4 0 0 1 8 0v4M12 15v3"/>',
    scan: '<path d="M3 8V3h5m8 0h5v5M3 16v5h5m8 0h5v-5M6 12h12"/>',
    back: '<path d="m15 4-8 8 8 8"/>'
  };
  return '<g transform="translate(' + x + ' ' + y + ') scale(' + size / 24 + ')" fill="none" stroke="' + color + '" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">' + paths[name] + '</g>';
}

function ring(cx, cy, r, fraction = 0.68, color = '#6B7179') {
  const start = -Math.PI / 2;
  const end = start - Math.PI * 2 * fraction;
  const sx = cx + r * Math.cos(start), sy = cy + r * Math.sin(start);
  const ex = cx + r * Math.cos(end), ey = cy + r * Math.sin(end);
  return '<path d="M' + sx + ' ' + sy + ' A' + r + ' ' + r + ' 0 ' + (fraction > 0.5 ? 1 : 0) + ' 0 ' + ex + ' ' + ey + '" fill="none" stroke="' + color + '" stroke-width="6" stroke-linecap="round"/>';
}

function header(n, first, second, subtitle, note, size = 96) {
  return group('brand',
    img(logo, 88, 80, 60, 60) + text(166, 124, 'Rotor', 40, 700) +
    line(292, 95, 292, 129, '#C2CDDF', 2) + text(312, 121, '身份验证器', 28, 500, muted) +
    text(992, 121, String(n).padStart(2, '0') + ' / 05', 24, 500, '#7D8DA7', 'text-anchor="end"')
  ) + group('headline',
    text(88, 295, first, size, 700, ink, 'letter-spacing="-2"') +
    text(88, 414, second, size, 700, blue, 'letter-spacing="-2"') +
    text(92, 492, subtitle, 32, 400, muted) +
    (note ? text(92, 541, note, 32, 400, muted) : '')
  );
}

function footer(left, right = 'HarmonyOS') {
  return group('footer',
    line(88, 1797, 992, 1797) +
    text(88, 1850, left, 24, 400, '#6B7A90') +
    text(992, 1850, right, 25, 500, '#52677F', 'text-anchor="end"')
  );
}

function art(file, y = 570, h = 1080) {
  return group('generated-artwork',
    img(png(join(dir, 'artwork', file)), 0, y, 1080, h, 'mask="url(#artMask)"')
  );
}

function avatar(x, y, name, size = 42) {
  if (name === 'Google') return img(google, x, y, size, size);
  if (name === 'Discord') return img(discord, x, y, size, size);
  return '<circle cx="' + (x + size / 2) + '" cy="' + (y + size / 2) + '" r="' + size / 2 + '" fill="#6350F6"/>' +
    text(x + size / 2, y + size * 0.74, name[0], size * 0.58, 500, '#FFFFFF', 'text-anchor="middle"');
}

function codeCard(x, y, w, name, code, note, { scale = 1, floating = false } = {}) {
  const h = 240 * scale;
  return '<g' + (floating ? ' filter="url(#shadow)"' : '') + '>' +
    rect(x, y, w, h, 34 * scale, floating ? 'url(#glass)' : '#FFFFFF', floating ? 'stroke="#FFFFFF" stroke-width="2"' : '') +
    avatar(x + 32 * scale, y + 26 * scale, name, 36 * scale) +
    text(x + 82 * scale, y + 54 * scale, name, 31 * scale, 500, '#171B23') +
    text(x + 32 * scale, y + 150 * scale, code, 88 * scale, 700, '#171B23', 'font-family="' + numFont + '" letter-spacing="1"') +
    ring(x + w - 78 * scale, y + 124 * scale, 32 * scale, 0.68) +
    text(x + 32 * scale, y + 206 * scale, note, 27 * scale, 400, '#747B85') + '</g>';
}

function features(items, y = 1701) {
  const w = 904 / items.length;
  return group('feature-notes', items.map((item, i) =>
    (i ? line(88 + i * w, y - 18, 88 + i * w, y + 17, '#CDD8E8') : '') +
    text(88 + w * (i + 0.5), y + 10, item, 28, 500, '#435973', 'text-anchor="middle"')
  ).join(''));
}

function createSvg(filename, title, content) {
  const value = '<?xml version="1.0" encoding="UTF-8"?>\n' +
    '<svg xmlns="http://www.w3.org/2000/svg" width="1080" height="1920" viewBox="0 0 1080 1920" role="img" aria-labelledby="title desc">\n' +
    '<title id="title">' + esc(title) + '</title>\n' +
    '<desc id="desc">Rotor 身份验证器宣传图。文字、功能图示与界面示意为可编辑矢量元素，立体插画为内嵌位图。账号与验证码为示例。</desc>\n' +
    defs + '\n<g font-family="' + font + '">\n' +
    rect(0, 0, 1080, 1920, 0, 'url(#paper)') + '\n' + content +
    '\n</g>\n</svg>\n';
  writeFileSync(join(dir, filename + '.svg'), value);
  execFileSync('rsvg-convert', ['-w', '1080', '-h', '1920', join(dir, filename + '.svg'), '-o', join(dir, filename + '.png')]);
}

createSvg('01-hero', '两步验证，离线也能取码',
  art('01-rotor-orbit.png', 567) +
  header(1, '两步验证，', '离线也能取码。', '扫码添加账号，在本机生成动态验证码。', '', 94) +
  group('code-demo',
    codeCard(172, 931, 736, 'Google', '481 925', '工作邮箱', { scale: 1.12, floating: true }) +
    '<g filter="url(#softShadow)">' + rect(684, 1250, 228, 70, 35) +
    icon('check', 711, 1271, 27, blue) + text(751, 1296, '点按复制', 27, 500, blue) + '</g>'
  ) +
  features(['离线生成', '扫码添加', '可选云同步']) +
  footer('功能示意，验证码为示例')
);

const toolbar = '<g filter="url(#softShadow)">' + rect(244, 1547, 592, 111, 56, '#FFFFFF', 'fill-opacity="0.96" stroke="#FFFFFF" stroke-width="3"') +
  ['search', 'plus', 'more'].map((name, i) =>
    icon(name, 321 + i * 184, 1563, 40, '#161B22') +
    text(341 + i * 184, 1639, ['搜索', '添加', '更多'][i], 24, 400, '#161B22', 'text-anchor="middle"')
  ).join('') + '</g>';

createSvg('02-codes', '验证码，点一下就复制',
  header(2, '验证码，', '点一下就复制。', '大字号显示，圆环提示剩余时间。', '支持搜索、拖动排序与左滑编辑。', 94) +
  group('app-interface-demo',
    '<g filter="url(#shadow)">' + rect(106, 621, 868, 1081, 58, '#F1F3F5', 'stroke="#FFFFFF" stroke-width="3"') + '</g>' +
    text(156, 724, 'Rotor', 66, 700, '#121619') +
    codeCard(145, 771, 790, 'Google', '481 925', '工作邮箱', { scale: 0.96 }) +
    codeCard(145, 1019, 790, 'Aliyun', '692 153', '云服务账号', { scale: 0.96 }) +
    codeCard(145, 1267, 790, 'Discord', '367 042', '游戏账号', { scale: 0.96 }) +
    toolbar
  ) +
  footer('界面示意，账号与验证码为示例')
);

function qrIllustration() {
  let result = '';
  const unit = 12, n = 25;
  function finder(x, y) {
    return rect(x * unit, y * unit, 7 * unit, 7 * unit, 10, ink) +
      rect((x + 1) * unit, (y + 1) * unit, 5 * unit, 5 * unit, 5, '#F3F8FF') +
      rect((x + 2) * unit, (y + 2) * unit, 3 * unit, 3 * unit, 4, ink);
  }
  for (let y = 0; y < n; y++) {
    for (let x = 0; x < n; x++) {
      if ((x < 8 && y < 8) || (x > 16 && y < 8) || (x < 8 && y > 16)) continue;
      if (((x * 13 + y * 7 + x * y * 3) % 11) < 5) result += rect(x * unit, y * unit, 10, 10, 2, ink);
    }
  }
  return finder(0, 0) + finder(18, 0) + finder(0, 18) + result;
}

createSvg('03-scan', '扫码添加，批量迁移',
  art('03-scan-glass.png', 528, 1080) +
  header(3, '扫码添加，', '批量迁移。', '识别相册二维码，也可手动输入密钥。', '支持 Google 身份验证器迁移二维码。') +
  group('qr-concept',
    '<g transform="translate(362 849) rotate(5) skewX(-3) scale(0.99)">' +
    qrIllustration() + '</g>'
  ) +
  group('import-demo',
    '<g filter="url(#shadow)">' + rect(128, 1395, 824, 195, 38, 'url(#glass)', 'stroke="#FFFFFF" stroke-width="2"') +
    '<circle cx="193" cy="1493" r="32" fill="#EAF1FF"/>' + icon('check', 175, 1475, 36, blue) +
    text(249, 1472, '一次导入多个账号', 35, 600) +
    text(249, 1530, '已存在的账号自动跳过', 29, 400, muted) + '</g>'
  ) +
  features(['扫码添加', '相册识别', '批量迁移']) +
  footer('功能示意，二维码为图形示意')
);

createSvg('04-backup', '加密备份，换机可恢复',
  art('04-backup-glass.png', 554) +
  header(4, '加密备份，', '换机可恢复。', '设置备份密码，导出所选账号。', '选择备份文件，输入密码即可恢复。') +
  group('backup-file-demo',
    '<g filter="url(#shadow)">' + rect(125, 1376, 830, 213, 40, 'url(#glass)', 'stroke="#FFFFFF" stroke-width="2"') +
    rect(158, 1411, 90, 90, 24, '#EAF1FF') + icon('file', 181, 1430, 44, blue) +
    text(276, 1454, 'Rotor.rotorbak', 38, 600) +
    text(276, 1501, '密码加密备份文件', 28, 400, muted) +
    line(157, 1530, 923, 1530, '#E2E9F4') +
    icon('lock', 160, 1547, 24, blue) + text(198, 1570, 'AES-256', 25, 500, blue) +
    text(923, 1570, '支持选择账号导出', 25, 400, muted, 'text-anchor="end"') + '</g>'
  ) +
  features(['密码加密', '导入恢复', '重复账号跳过']) +
  footer('功能示意')
);

createSvg('05-sync', '你的账号，多设备同步',
  art('05-sync-glass.png', 564) +
  header(5, '你的账号，', '多设备同步。', '通过华为云空间同步账号与密钥。', '适用于同一华为账号的 HarmonyOS 设备。', 94) +
  group('sync-status-demo',
    '<g filter="url(#shadow)">' + rect(127, 1395, 826, 196, 39, 'url(#glass)', 'stroke="#FFFFFF" stroke-width="2"') +
    icon('cloud', 168, 1433, 47, blue) +
    text(243, 1466, '云同步', 34, 600) +
    rect(816, 1423, 92, 52, 26, blue) +
    '<circle cx="882" cy="1449" r="21" fill="#FFFFFF"/>' +
    line(168, 1500, 908, 1500, '#DDE6F3') +
    icon('check', 171, 1528, 27, blue) +
    text(213, 1555, '已与云空间同步', 28, 500, '#426080') + '</g>'
  ) +
  text(540, 1689, '需同时开启应用内与系统云空间的同步开关', 28, 400, muted, 'text-anchor="middle"') +
  footer('功能示意，同步可按需开启')
);

const names = ['01-hero', '02-codes', '03-scan', '04-backup', '05-sync'];
const overviewDir = join(dir, '.preview');
mkdirSync(overviewDir, { recursive: true });
for (const name of names) {
  execFileSync('magick', [join(dir, name + '.png'), '-resize', '324x576', join(overviewDir, name + '.png')]);
}
execFileSync('magick', [
  'montage', ...names.map(name => join(overviewDir, name + '.png')),
  '-tile', '5x1', '-geometry', '324x576+12+12', '-background', '#DCE5F1',
  join(dir, 'overview.png')
]);
for (const name of names) {
  const size = (statSync(join(dir, name + '.png')).size / 1024 / 1024).toFixed(2);
  console.log(name + ': 1080x1920, ' + size + ' MiB');
}
