// 内置图标映射，未命中返回默认 globe
const ICON_MAP: Record<string, Resource> = {};

export function iconForName(name: string): Resource {
  const key = (name || '').trim().toLowerCase();
  if (ICON_MAP[key]) {
    return ICON_MAP[key];
  }
  return $r('app.media.icon_default');
}
