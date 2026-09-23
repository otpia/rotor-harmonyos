// 内置 issuer 品牌图标，未命中时返回 undefined，由首字母头像兜底
const ICON_MAP: Record<string, Resource> = {
  'sony': $r('app.media.issuer_sony'),
  'google': $r('app.media.issuer_google'),
  'discord': $r('app.media.issuer_discord'),
};

// 首字母头像背景色，取系统多彩色板，按名称哈希稳定选色
const AVATAR_COLORS: Resource[] = [
  $r('sys.color.multi_color_01'),
  $r('sys.color.multi_color_02'),
  $r('sys.color.multi_color_03'),
  $r('sys.color.multi_color_04'),
  $r('sys.color.multi_color_05'),
  $r('sys.color.multi_color_06'),
  $r('sys.color.multi_color_07'),
  $r('sys.color.multi_color_08'),
  $r('sys.color.multi_color_09'),
  $r('sys.color.multi_color_10'),
  $r('sys.color.multi_color_11')
];

export function issuerImage(name: string): Resource | undefined {
  const key = (name || '').trim().toLowerCase();
  const r = ICON_MAP[key];
  return r ? r : undefined;
}

export function avatarInitial(name: string): string {
  const s = (name || '').trim();
  if (s.length === 0) {
    return '?';
  }
  return s.substring(0, 1).toUpperCase();
}

export function avatarColor(name: string): Resource {
  const s = (name || '').trim().toLowerCase();
  let h = 0;
  for (let i = 0; i < s.length; i++) {
    h = (h * 31 + s.charCodeAt(i)) % 1000003;
  }
  return AVATAR_COLORS[h % AVATAR_COLORS.length];
}
