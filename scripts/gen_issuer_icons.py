# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow"]
# ///

# 生成 issuer 品牌图标资源与匹配数据
# 服务表与图标取自 2FAS Auth 安卓仓库（GPL-3.0），scripts/issuer_extra 下是 2FAS 未收录的补充服务
# 用法：uv run scripts/gen_issuer_icons.py

import io
import json
import os
import re
import tarfile
import urllib.request

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, 'entry', 'src', 'main', 'resources')
BASE_MEDIA = os.path.join(RES, 'base', 'media')
DARK_MEDIA = os.path.join(RES, 'dark', 'media')
DATA_ETS = os.path.join(ROOT, 'entry', 'src', 'main', 'ets', 'utils', 'IssuerIconData.ets')
EXTRA_DIR = os.path.join(ROOT, 'scripts', 'issuer_extra')
REPO = 'twofas/2fas-android'
BRANCH = 'develop'
ASSETS = '/parsers/src/main/assets/'
PREFIX = 'issuer_'

# 深色模式卡片底色，用来判断图标在深色背景上是否看得清
DARK_BG = (34, 34, 34)
# 深色模式下给看不清的图标垫的浅色圆底
PLATE = (237, 237, 237)

# 2FAS 未收录的服务：资源键、名称、包含即命中的关键词
EXTRA = [
    ('baiducloud', '百度智能云', ['baidu', '百度']),
    ('volcengine', '火山引擎', ['volcengine', '火山引擎']),
    ('qiniu', '七牛云', ['qiniu', '七牛']),
    ('gitee', 'Gitee', ['gitee', '码云']),
    ('1panel', '1Panel', ['1panel']),
]

# 按 2FAS 服务名追加的关键词，包含即命中
ALIASES = {
    'Google': ['谷歌'],
    'Microsoft': ['微软'],
    'Amazon': ['亚马逊'],
    'Alibaba Cloud': ['阿里云', 'alibabacloud', 'aliyun'],
    'Tencent Cloud': ['腾讯云', 'tencentcloud', 'qcloud'],
    'Huawei': ['华为'],
    'Binance': ['币安'],
    'OKX': ['欧易'],
    'Huobi': ['火币', 'htx'],
    'Sony': ['索尼'],
    'Nintendo': ['任天堂'],
    'Synology': ['群晖'],
    'QNAP': ['威联通'],
    'Asus': ['华硕'],
    'Lark': ['飞书', 'feishu'],
}

# 与 IssuerIconData.ets 中 matcher 的取值一致
MATCHERS = {'contains': 0, 'starts_with': 1, 'ends_with': 2, 'equals': 3, 'regex': 4}


def fetch(url):
    req = urllib.request.Request(url, headers={'User-Agent': 'rotor-gen-issuer-icons'})
    with urllib.request.urlopen(req, timeout=300) as r:
        return r.read()


def load_2fas():
    try:
        ref = json.loads(fetch(f'https://api.github.com/repos/{REPO}/commits/{BRANCH}'))['sha']
    except Exception as e:
        print(f'取不到 {BRANCH} 的提交号，直接用分支名：{e}')
        ref = BRANCH
    services, icons = None, {}
    data = fetch(f'https://codeload.github.com/{REPO}/tar.gz/{ref}')
    with tarfile.open(fileobj=io.BytesIO(data), mode='r:gz') as tar:
        for m in tar:
            if not m.isfile() or ASSETS not in m.name:
                continue
            rel = m.name.split(ASSETS, 1)[1]
            if rel == 'services.json':
                services = json.load(tar.extractfile(m))
            elif rel.startswith('icons/') and rel.endswith('.png'):
                icons[rel[len('icons/'):-len('.png')]] = tar.extractfile(m).read()
    if services is None:
        raise SystemExit('压缩包里没有 services.json')
    return ref, services, icons


def linear(c):
    c = c / 255
    return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4


LIN = [linear(c) for c in range(256)]
BG_L = 0.2126 * LIN[DARK_BG[0]] + 0.7152 * LIN[DARK_BG[1]] + 0.0722 * LIN[DARK_BG[2]]


# 透明底，且过半可见像素与深色背景的对比度不足 1.6，视为深色模式下看不清
def unreadable_on_dark(img):
    raw = img.tobytes()
    total = len(raw) // 4
    vis = bad = 0
    for k in range(0, len(raw), 4):
        if raw[k + 3] <= 128:
            continue
        vis += 1
        lum = 0.2126 * LIN[raw[k]] + 0.7152 * LIN[raw[k + 1]] + 0.0722 * LIN[raw[k + 2]]
        if (max(lum, BG_L) + 0.05) / (min(lum, BG_L) + 0.05) < 1.6:
            bad += 1
    return vis > 0 and vis / total < 0.95 and bad / vis > 0.5


# 浅色圆底居中放原图，原图缩到圆内能完整放下方形的大小
def plated(img):
    size = img.size[0]
    big = size * 4
    mask = Image.new('L', (big, big), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, big - 1, big - 1), fill=255)
    out = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    out.paste(Image.new('RGBA', (size, size), PLATE + (255,)), (0, 0), mask.resize((size, size), Image.LANCZOS))
    inner = round(size * 0.7)
    off = (size - inner) // 2
    out.alpha_composite(img.resize((inner, inner), Image.LANCZOS), (off, off))
    return out


def save_webp(img, directory, key):
    img.save(os.path.join(directory, f'{PREFIX}{key}.webp'), 'WEBP', lossless=True, method=6)


def clean(directory):
    os.makedirs(directory, exist_ok=True)
    for f in os.listdir(directory):
        if f.startswith(PREFIX):
            os.remove(os.path.join(directory, f))


def slug(name, sid, used):
    base = re.sub(r'[^a-z0-9]+', '_', name.lower()).strip('_') or 'id_' + sid.replace('-', '')[:12]
    key, n = base, 2
    while key in used:
        key, n = f'{base}_{n}', n + 1
    used.add(key)
    return key


# 服务名与 issuer 别名用于精确匹配，issuer 与 label 两类规则都作用在账号名称上，去重后输出
def convert_rules(service):
    names, rules, seen = {service['name'].strip().lower()}, [], set()
    for x in service.get('issuers') or []:
        if x.strip():
            names.add(x.strip().lower())
    for r in service.get('match_rules') or []:
        text = (r.get('text') or '').strip()
        if not text:
            continue
        matcher = MATCHERS.get(r.get('matcher'), 0)
        ignore_case = r.get('ignore_case') is not False
        if matcher == 3 and ignore_case:
            names.add(text.lower())
            continue
        if ignore_case and matcher != 4:
            text = text.lower()
        rule = (matcher, text, ignore_case)
        if rule not in seen:
            seen.add(rule)
            rules.append(rule)
    return sorted(names), rules


def ts_str(s):
    return "'" + s.replace('\\', '\\\\').replace("'", "\\'") + "'"


def write_ets(ref, entries):
    lines = [
        '// 由 scripts/gen_issuer_icons.py 生成，勿手改',
        f'// 服务图标与匹配规则取自 2FAS Auth 安卓仓库 {REPO}（GPL-3.0，提交 {ref[:7]}），另含 scripts/issuer_extra 下的补充服务',
        '',
        'export interface IssuerRule {',
        '  // 0 包含，1 开头，2 结尾，3 相等，4 正则',
        '  matcher: number;',
        '  text: string;',
        '  ignoreCase: boolean;',
        '}',
        '',
        'export interface IssuerIconEntry {',
        '  // 资源键，手动选择时以 lib: 前缀存入账号的 iconKey',
        '  key: string;',
        '  // 服务显示名，用于图标选择器的展示与搜索',
        '  title: string;',
        '  icon: Resource;',
        '  // 小写后与账号名称精确比较',
        '  names: string[];',
        '  rules: IssuerRule[];',
        '}',
        '',
        'export const ISSUER_ICONS: IssuerIconEntry[] = [',
    ]
    for e in entries:
        names = ', '.join(ts_str(n) for n in e['names'])
        rules = ', '.join(
            f'{{ matcher: {m}, text: {ts_str(t)}, ignoreCase: {"true" if ic else "false"} }}' for m, t, ic in e['rules'])
        lines.append(f"  {{ key: {ts_str(e['key'])}, title: {ts_str(e['title'])}, icon: $r('app.media.{PREFIX}{e['key']}'), "
                     f"names: [{names}], rules: [{rules}] }},")
    lines.append('];')
    with open(DATA_ETS, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines) + '\n')


def main():
    ref, services, icons = load_2fas()
    clean(BASE_MEDIA)
    clean(DARK_MEDIA)
    used, entries = set(), []
    paired = plate = 0
    found = set()
    for s in services:
        cols = s.get('icons_collections') or []
        group = (cols[0].get('icons') or []) if cols else []
        light = next((i for i in group if i.get('type') != 'dark'), None)
        if light is None or light['id'] not in icons:
            continue
        dark = next((i for i in group if i.get('type') == 'dark'), None)
        key = slug(s['name'], s['id'], used)
        img = Image.open(io.BytesIO(icons[light['id']])).convert('RGBA')
        save_webp(img, BASE_MEDIA, key)
        if dark is not None and dark['id'] in icons:
            save_webp(Image.open(io.BytesIO(icons[dark['id']])).convert('RGBA'), DARK_MEDIA, key)
            paired += 1
        elif unreadable_on_dark(img):
            save_webp(plated(img), DARK_MEDIA, key)
            plate += 1
        names, rules = convert_rules(s)
        for kw in ALIASES.get(s['name'], []):
            found.add(s['name'])
            rules.append((0, kw.lower(), True))
        entries.append({'key': key, 'title': s['name'].strip(), 'names': names, 'rules': rules})
    for key, name, keywords in EXTRA:
        if key in used:
            raise SystemExit(f'补充服务的键与 2FAS 重复：{key}')
        used.add(key)
        img = Image.open(os.path.join(EXTRA_DIR, f'{key}.png')).convert('RGBA')
        save_webp(img, BASE_MEDIA, key)
        if unreadable_on_dark(img):
            save_webp(plated(img), DARK_MEDIA, key)
            plate += 1
        entries.append({'key': key, 'title': name, 'names': [name.lower()], 'rules': [(0, k.lower(), True) for k in keywords]})
    # 按显示名排序，选择器里按字母顺序浏览
    entries.sort(key=lambda e: e['title'].casefold())
    write_ets(ref, entries)
    missing = sorted(set(ALIASES) - found)
    if missing:
        print(f'以下别名对应的 2FAS 服务不存在：{missing}')
    print(f'提交 {ref[:7]}：图标 {len(entries)} 个，2FAS 自带深色版 {paired} 个，垫浅色圆底 {plate} 个')


if __name__ == '__main__':
    main()
