// 内置图标映射，未命中返回默认地球
const ICON_MAP: Record<string, Resource> = {
  'sony': $r('app.media.issuer_sony'),
  'google': $r('app.media.issuer_google'),
  'discord': $r('app.media.issuer_discord'),
};

export function iconForName(name: string): Resource {
  const key = (name || '').trim().toLowerCase();
  if (ICON_MAP[key]) {
    return ICON_MAP[key];
  }
  return $r('app.media.icon_default');
}
