import { ISSUER_ICONS, IssuerRule } from './IssuerIconData';

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

// 不超过这个长度的英文数字关键词按整词匹配，避免 Rev 这类缩写配上 Revolution
const SHORT_WORD = 3;
// 服务名作为整词出现在账号名称里也算命中，服务名至少要有这个长度
const NAME_WORD_MIN = 4;
// 名称里的邮箱多是登录账号，不代表服务，匹配前去掉
const EMAIL = /[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+/g;

// 名称到品牌图标的匹配结果，未命中存 null
const matchCache: Map<string, Resource | null> = new Map();
// 正则规则的编译结果，编译失败存 null
const regexCache: Map<string, RegExp | null> = new Map();

function isWordChar(c: string): boolean {
  return c.length > 0 && /[a-z0-9]/i.test(c);
}

// 中文等关键词与英文连写很常见，只有纯英文数字的关键词才按整词匹配
function isAsciiWord(t: string): boolean {
  return /^[a-z0-9]+$/i.test(t);
}

function isAsciiText(t: string): boolean {
  return /^[\x20-\x7e]+$/.test(t);
}

function isWordAt(s: string, at: number, len: number): boolean {
  return !isWordChar(s.charAt(at - 1)) && !isWordChar(s.charAt(at + len));
}

function containsWord(s: string, word: string): boolean {
  let from = 0;
  while (from <= s.length - word.length) {
    const at = s.indexOf(word, from);
    if (at < 0) {
      return false;
    }
    if (isWordAt(s, at, word.length)) {
      return true;
    }
    from = at + 1;
  }
  return false;
}

function ruleRegex(rule: IssuerRule): RegExp | null {
  const key = (rule.ignoreCase ? 'i:' : 's:') + rule.text;
  const cached = regexCache.get(key);
  if (cached !== undefined) {
    return cached;
  }
  let re: RegExp | null = null;
  try {
    re = new RegExp(rule.text, rule.ignoreCase ? 'i' : '');
  } catch (e) {
    console.error('[IssuerIcon.ruleRegex]', rule.text, e);
  }
  regexCache.set(key, re);
  return re;
}

// 返回规则命中的文本长度，未命中返回 0；多条命中时取最长的一条，越长越具体
function ruleHit(rule: IssuerRule, raw: string, lower: string): number {
  if (rule.matcher === 4) {
    const re = ruleRegex(rule);
    const m = re !== null ? re.exec(raw) : null;
    return m !== null ? Math.max(m[0].length, 1) : 0;
  }
  const s = rule.ignoreCase ? lower : raw;
  const t = rule.text;
  const short = t.length <= SHORT_WORD && isAsciiWord(t);
  if (rule.matcher === 0) {
    return (short ? containsWord(s, t) : s.includes(t)) ? t.length : 0;
  }
  if (rule.matcher === 1) {
    return s.startsWith(t) && (!short || isWordAt(s, 0, t.length)) ? t.length : 0;
  }
  if (rule.matcher === 2) {
    return s.endsWith(t) && (!short || isWordAt(s, s.length - t.length, t.length)) ? t.length : 0;
  }
  return s === t ? t.length : 0;
}

// 先比服务名与别名是否完全相同，再在规则与整词出现的服务名中取命中最长的
function findIcon(raw: string): Resource | null {
  const lower = raw.toLowerCase();
  for (const e of ISSUER_ICONS) {
    if (e.names.includes(lower)) {
      return e.icon;
    }
  }
  let best: Resource | null = null;
  let bestLen = 0;
  for (const e of ISSUER_ICONS) {
    for (const r of e.rules) {
      const len = ruleHit(r, raw, lower);
      if (len > bestLen) {
        best = e.icon;
        bestLen = len;
      }
    }
    for (const n of e.names) {
      if (n.length >= NAME_WORD_MIN && n.length > bestLen &&
        (isAsciiText(n) ? containsWord(lower, n) : lower.includes(n))) {
        best = e.icon;
        bestLen = n.length;
      }
    }
  }
  return best;
}

// 按账号名称匹配内置品牌图标，深浅色版本由资源目录自动切换，未命中返回 undefined，由首字母头像兜底
export function issuerImage(name: string): Resource | undefined {
  const issuer = (name || '').replace(EMAIL, ' ').trim();
  if (issuer.length === 0) {
    return undefined;
  }
  let icon = matchCache.get(issuer);
  if (icon === undefined) {
    icon = findIcon(issuer);
    matchCache.set(issuer, icon);
  }
  return icon !== null ? icon : undefined;
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
