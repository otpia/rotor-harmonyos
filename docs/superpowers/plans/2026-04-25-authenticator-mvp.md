# Rotor Authenticator MVP+Scan Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a HarmonyOS NEXT TOTP authenticator app — list, manual add, QR-code scan, edit, swipe-delete, search, copy, light/dark theme.

**Architecture:** ArkTS + ArkUI declarative. Sensitive secrets only in Asset Kit (alias=`otp_secret_<id>`). Metadata in `relationalStore` (SQLite). TOTP via `@kit.CryptoArchitectureKit` HMAC-SHA1. Scanning via `@kit.ScanKit`.

**Tech Stack:** HarmonyOS NEXT (API 23), ArkTS, ArkUI, `@kit.AssetStoreKit`, `@kit.ArkData` (relationalStore), `@kit.CryptoArchitectureKit`, `@kit.ScanKit`, `@ohos.pasteboard`, hypium for unit tests.

**Spec reference:** `docs/superpowers/specs/2026-04-25-authenticator-design.md`

---

## File Structure

Created (all under `entry/src/main/ets/`):

```
model/
  OtpAccount.ets         # OtpAccount interface, OtpType enum
utils/
  Base32.ets             # base32 encode/decode (RFC 4648)
  HmacSha1.ets           # HMAC via cryptoFramework
  OtpAuthUri.ets         # parse otpauth:// URI
  IssuerIcon.ets         # name → built-in icon resource map
services/
  OtpEngine.ets          # TOTP/HOTP code generation
  SecretVault.ets        # Asset Kit wrapper
  OtpAccountStore.ets    # relationalStore wrapper
  TickerService.ets      # 1Hz tick singleton
components/
  ProgressRing.ets       # 30s ring (3-color)
  CopyToast.ets          # bottom "已复制" pill
  SearchBar.ets          # search input
  PlusMenuPopup.ets      # FAB popup
  TypeSheet.ets          # type half-sheet
  DeleteConfirmDialog.ets# bottom confirm dialog
  OtpItem.ets            # list card
pages/
  Index.ets              # home (REPLACES existing template)
  EditPage.ets           # add/edit form
  ScanPage.ets           # camera scan
```

Tests (under `entry/src/ohosTest/ets/test/`):

```
Base32.test.ets
OtpEngine.test.ets
OtpAuthUri.test.ets
```

Resource changes:

- `entry/src/main/resources/base/element/color.json` — token additions
- `entry/src/main/resources/dark/element/color.json` — dark variants
- `entry/src/main/resources/base/element/string.json` — UI strings
- `entry/src/main/resources/base/profile/main_pages.json` — pages list
- `entry/src/main/module.json5` — CAMERA permission + nav
- `entry/src/main/resources/base/media/foreground.png` and `background.png` — replaced with Sketch appicon
- `AppScope/resources/base/element/string.json` — app_name="Rotor"

---

## Task 1: Resources, permissions, app icon, page registry

**Files:**
- Modify: `AppScope/resources/base/element/string.json`
- Modify: `entry/src/main/resources/base/element/string.json`
- Modify: `entry/src/main/resources/base/element/color.json`
- Modify: `entry/src/main/resources/dark/element/color.json`
- Modify: `entry/src/main/resources/base/profile/main_pages.json`
- Modify: `entry/src/main/module.json5`
- Replace: `entry/src/main/resources/base/media/foreground.png`, `background.png`

- [ ] **Step 1.1: Set app name**

Edit `AppScope/resources/base/element/string.json`: ensure `app_name` value is `"Rotor"`.

- [ ] **Step 1.2: Add UI strings**

Replace `entry/src/main/resources/base/element/string.json` with:

```json
{
  "string": [
    { "name": "module_desc", "value": "Rotor module" },
    { "name": "EntryAbility_desc", "value": "Rotor authenticator" },
    { "name": "EntryAbility_label", "value": "Rotor" },
    { "name": "search_placeholder", "value": "搜索" },
    { "name": "label_name", "value": "名称" },
    { "name": "label_note", "value": "描述" },
    { "name": "label_secret", "value": "秘钥" },
    { "name": "label_type", "value": "类型" },
    { "name": "type_totp", "value": "基于时间" },
    { "name": "type_hotp", "value": "基于计数器" },
    { "name": "type_hotp_disabled", "value": "暂不支持" },
    { "name": "menu_input_secret", "value": "输入设置密钥" },
    { "name": "menu_scan_qr", "value": "扫描二维码" },
    { "name": "btn_cancel", "value": "取消" },
    { "name": "btn_delete", "value": "删除" },
    { "name": "btn_edit", "value": "编辑" },
    { "name": "btn_save", "value": "保存" },
    { "name": "toast_copied", "value": "已复制" },
    { "name": "delete_confirm", "value": "是否要删除 %s？" },
    { "name": "edit_title", "value": "编辑" },
    { "name": "add_title", "value": "添加" },
    { "name": "empty_hint", "value": "点击右下角加号添加账号" },
    { "name": "scan_invalid", "value": "未识别的二维码" },
    { "name": "secret_invalid", "value": "秘钥格式不正确" },
    { "name": "name_required", "value": "请填写名称" }
  ]
}
```

- [ ] **Step 1.3: Add color tokens (light)**

Replace `entry/src/main/resources/base/element/color.json` with:

```json
{
  "color": [
    { "name": "start_window_background", "value": "#F2F3F5" },
    { "name": "bg_app", "value": "#F2F3F5" },
    { "name": "bg_card", "value": "#FFFFFF" },
    { "name": "bg_card_active", "value": "#E5E5EA" },
    { "name": "text_primary", "value": "#000000" },
    { "name": "text_secondary", "value": "#8E8E93" },
    { "name": "text_placeholder", "value": "#AEAEB2" },
    { "name": "accent_blue", "value": "#2772FF" },
    { "name": "accent_red", "value": "#FF3B30" },
    { "name": "ring_normal", "value": "#000000" },
    { "name": "ring_warn", "value": "#C7C7CC" },
    { "name": "ring_danger", "value": "#FF3B30" },
    { "name": "divider", "value": "#E5E5EA" },
    { "name": "scrim", "value": "#80000000" }
  ]
}
```

- [ ] **Step 1.4: Add color tokens (dark)**

Replace `entry/src/main/resources/dark/element/color.json` with:

```json
{
  "color": [
    { "name": "start_window_background", "value": "#000000" },
    { "name": "bg_app", "value": "#000000" },
    { "name": "bg_card", "value": "#1C1C1E" },
    { "name": "bg_card_active", "value": "#2C2C2E" },
    { "name": "text_primary", "value": "#FFFFFF" },
    { "name": "text_secondary", "value": "#8E8E93" },
    { "name": "text_placeholder", "value": "#636366" },
    { "name": "accent_blue", "value": "#2772FF" },
    { "name": "accent_red", "value": "#FF3B30" },
    { "name": "ring_normal", "value": "#FFFFFF" },
    { "name": "ring_warn", "value": "#5A5A5C" },
    { "name": "ring_danger", "value": "#FF3B30" },
    { "name": "divider", "value": "#2C2C2E" },
    { "name": "scrim", "value": "#80000000" }
  ]
}
```

- [ ] **Step 1.5: Register pages in main_pages.json**

Replace `entry/src/main/resources/base/profile/main_pages.json` with:

```json
{
  "src": [
    "pages/Index",
    "pages/EditPage",
    "pages/ScanPage"
  ]
}
```

- [ ] **Step 1.6: Add CAMERA permission**

Edit `entry/src/main/module.json5`: add a `requestPermissions` array inside `module` (after `pages`):

```json5
"requestPermissions": [
  {
    "name": "ohos.permission.CAMERA",
    "reason": "$string:module_desc",
    "usedScene": {
      "abilities": [ "EntryAbility" ],
      "when": "inuse"
    }
  }
]
```

- [ ] **Step 1.7: Replace app icon PNGs**

Run from project root:

```bash
curl -sS -X POST http://localhost:31126/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","id":99,"method":"tools/call","params":{"name":"run_code","arguments":{"title":"Export icon foreground+background","script":"const sketch=require(\"sketch\");const f=sketch.find(\"#1E024F09-F8E1-4EAB-962D-FACBD89F3631\")[0];sketch.export(f,{output:\"/Users/liasica/projects/deskotp/rotor-harmonyos/entry/src/main/resources/base/media\",filename:\"foreground.png\",formats:[\"png\"],scales:\"2\"});console.log(\"ok\");"}}}'
```

The same icon is used as foreground; background stays the existing flat color (HarmonyOS layered icon). For MVP, copy foreground to also overwrite `background.png`:

```bash
cp entry/src/main/resources/base/media/foreground.png entry/src/main/resources/base/media/background.png
```

- [ ] **Step 1.8: Build to verify**

```bash
hvigorw clean && hvigorw assembleHap --mode module -p product=default -p buildMode=debug
```

Expected: BUILD SUCCESSFUL.

- [ ] **Step 1.9: Commit**

```bash
git add AppScope entry/src/main/resources entry/src/main/module.json5
git commit -m "chore(rotor): bootstrap resources, permissions and app icon"
```

---

## Task 2: Model types

**Files:**
- Create: `entry/src/main/ets/model/OtpAccount.ets`

- [ ] **Step 2.1: Write the file**

```ts
// 账号类型枚举（MVP 仅使用 TOTP）
export enum OtpType {
  TOTP = 'totp',
  HOTP = 'hotp'
}

// 账号元数据；秘钥不在此结构中，仅存于 Asset Kit
export interface OtpAccount {
  id: string;
  name: string;
  note: string;
  type: OtpType;
  period: number;
  digits: number;
  algorithm: 'SHA1' | 'SHA256' | 'SHA512';
  counter: number;
  iconKey: string;
  orderIndex: number;
  createdAt: number;
  updatedAt: number;
}

export function defaultAccount(): OtpAccount {
  const now = Date.now();
  return {
    id: '',
    name: '',
    note: '',
    type: OtpType.TOTP,
    period: 30,
    digits: 6,
    algorithm: 'SHA1',
    counter: 0,
    iconKey: '',
    orderIndex: 0,
    createdAt: now,
    updatedAt: now
  };
}
```

- [ ] **Step 2.2: Commit**

```bash
git add entry/src/main/ets/model
git commit -m "feat(rotor): add OtpAccount model and OtpType enum"
```

---

## Task 3: Base32 codec (TDD)

**Files:**
- Create: `entry/src/main/ets/utils/Base32.ets`
- Test: `entry/src/ohosTest/ets/test/Base32.test.ets`

- [ ] **Step 3.1: Write failing tests**

Create `entry/src/ohosTest/ets/test/Base32.test.ets`:

```ts
import { describe, it, expect } from '@ohos/hypium';
import { base32Decode, base32Normalize } from '../../../../main/ets/utils/Base32';

export default function base32Tests() {
  describe('Base32', () => {
    it('decodes RFC 4648 vectors', 0, () => {
      // RFC 4648 §10
      const cases: [string, number[]][] = [
        ['', []],
        ['MY======', [0x66]],
        ['MZXQ====', [0x66, 0x6f]],
        ['MZXW6===', [0x66, 0x6f, 0x6f]],
        ['MZXW6YQ=', [0x66, 0x6f, 0x6f, 0x62]],
        ['MZXW6YTB', [0x66, 0x6f, 0x6f, 0x62, 0x61]],
        ['MZXW6YTBOI======', [0x66, 0x6f, 0x6f, 0x62, 0x61, 0x72]]
      ];
      for (const c of cases) {
        const out = Array.from(base32Decode(c[0]));
        expect(out.length).assertEqual(c[1].length);
        for (let i = 0; i < out.length; i++) {
          expect(out[i]).assertEqual(c[1][i]);
        }
      }
    });

    it('tolerates lowercase, spaces and dashes', 0, () => {
      const a = Array.from(base32Decode('jbsw y3dp'));
      const b = Array.from(base32Decode('JBSWY3DP'));
      expect(a.length).assertEqual(b.length);
      for (let i = 0; i < a.length; i++) {
        expect(a[i]).assertEqual(b[i]);
      }
    });

    it('rejects illegal characters', 0, () => {
      let threw = false;
      try { base32Decode('!!!'); } catch (e) { threw = true; }
      expect(threw).assertTrue();
    });

    it('normalizes input', 0, () => {
      expect(base32Normalize(' jb-sw y3 dp ')).assertEqual('JBSWY3DP');
    });
  });
}
```

Register in `entry/src/ohosTest/ets/test/List.test.ets` (append `base32Tests()` call inside the existing test list function).

- [ ] **Step 3.2: Run tests to confirm they fail**

In DevEco Studio: right-click `ohosTest` → Run. Expected: import error / module-not-found for `Base32`.

- [ ] **Step 3.3: Implement Base32**

Create `entry/src/main/ets/utils/Base32.ets`:

```ts
const ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

export function base32Normalize(input: string): string {
  return input.replace(/[\s-]/g, '').toUpperCase().replace(/=+$/, '');
}

export function base32Decode(input: string): Uint8Array {
  const norm = base32Normalize(input);
  if (norm.length === 0) {
    return new Uint8Array(0);
  }
  const out: number[] = [];
  let buffer = 0;
  let bits = 0;
  for (let i = 0; i < norm.length; i++) {
    const ch = norm.charAt(i);
    const idx = ALPHABET.indexOf(ch);
    if (idx < 0) {
      throw new Error(`invalid base32 character: ${ch}`);
    }
    buffer = (buffer << 5) | idx;
    bits += 5;
    if (bits >= 8) {
      bits -= 8;
      out.push((buffer >> bits) & 0xff);
    }
  }
  return new Uint8Array(out);
}

export function isValidBase32(input: string): boolean {
  try {
    return base32Decode(input).length > 0;
  } catch (_e) {
    return false;
  }
}
```

- [ ] **Step 3.4: Re-run tests**

Expected: all 4 cases PASS.

- [ ] **Step 3.5: Commit**

```bash
git add entry/src/main/ets/utils/Base32.ets entry/src/ohosTest/ets/test/Base32.test.ets entry/src/ohosTest/ets/test/List.test.ets
git commit -m "feat(rotor): add base32 codec with RFC 4648 tests"
```

---

## Task 4: HMAC-SHA1 wrapper

**Files:**
- Create: `entry/src/main/ets/utils/HmacSha1.ets`

- [ ] **Step 4.1: Implement using cryptoFramework**

```ts
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import buffer from '@ohos.buffer';

// 计算 HMAC，algo 取值 SHA1/SHA256/SHA512
export async function hmac(algo: string, key: Uint8Array, message: Uint8Array): Promise<Uint8Array> {
  const mac = cryptoFramework.createMac(`HMAC|${algo}`);
  const symKeyGen = cryptoFramework.createSymKeyGenerator(`HMAC|${algo}`);
  const keyBlob: cryptoFramework.DataBlob = { data: key };
  const symKey = await symKeyGen.convertKey(keyBlob);
  await mac.init(symKey);
  await mac.update({ data: message } as cryptoFramework.DataBlob);
  const result = await mac.doFinal();
  return new Uint8Array(result.data);
}

// 把 64 位整数（毫秒级 / 计数器）编码为 8 字节大端
export function uint64ToBytesBE(value: number): Uint8Array {
  const out = new Uint8Array(8);
  // JS number is 53-bit safe; counter <= 2^53 is sufficient for TOTP
  let hi = Math.floor(value / 0x100000000);
  let lo = value >>> 0;
  out[0] = (hi >>> 24) & 0xff;
  out[1] = (hi >>> 16) & 0xff;
  out[2] = (hi >>> 8) & 0xff;
  out[3] = hi & 0xff;
  out[4] = (lo >>> 24) & 0xff;
  out[5] = (lo >>> 16) & 0xff;
  out[6] = (lo >>> 8) & 0xff;
  out[7] = lo & 0xff;
  return out;
}
```

- [ ] **Step 4.2: Commit**

```bash
git add entry/src/main/ets/utils/HmacSha1.ets
git commit -m "feat(rotor): add HMAC wrapper over CryptoArchitectureKit"
```

---

## Task 5: TOTP engine (TDD against RFC 6238 vectors)

**Files:**
- Create: `entry/src/main/ets/services/OtpEngine.ets`
- Test: `entry/src/ohosTest/ets/test/OtpEngine.test.ets`

- [ ] **Step 5.1: Write failing tests**

```ts
import { describe, it, expect } from '@ohos/hypium';
import { totp, formatGroups } from '../../../../main/ets/services/OtpEngine';

// RFC 6238 测试向量：seed = "12345678901234567890"
// base32 编码后为 "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"
const SECRET = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';

export default function otpEngineTests() {
  describe('OtpEngine', () => {
    it('matches RFC 6238 vector at T=59', 0, async () => {
      const code = await totp(SECRET, 59 * 1000, 30, 8, 'SHA1');
      expect(code).assertEqual('94287082');
    });

    it('matches RFC 6238 vector at T=1111111109', 0, async () => {
      const code = await totp(SECRET, 1111111109 * 1000, 30, 8, 'SHA1');
      expect(code).assertEqual('07081804');
    });

    it('truncates to 6 digits with leading zeros', 0, async () => {
      const code = await totp(SECRET, 59 * 1000, 30, 6, 'SHA1');
      expect(code.length).assertEqual(6);
    });

    it('formatGroups inserts middle space for 6 digits', 0, () => {
      expect(formatGroups('123456')).assertEqual('123 456');
    });
  });
}
```

Register in `List.test.ets` (`otpEngineTests()`).

- [ ] **Step 5.2: Run to confirm fail**

Expected: import error.

- [ ] **Step 5.3: Implement OtpEngine**

```ts
import { base32Decode } from '../utils/Base32';
import { hmac, uint64ToBytesBE } from '../utils/HmacSha1';

export async function totp(
  secretBase32: string,
  nowMs: number,
  period: number,
  digits: number,
  algorithm: 'SHA1' | 'SHA256' | 'SHA512'
): Promise<string> {
  const t = Math.floor(nowMs / 1000 / period);
  const msg = uint64ToBytesBE(t);
  const key = base32Decode(secretBase32);
  const mac = await hmac(algorithm, key, msg);
  const offset = mac[mac.length - 1] & 0x0f;
  const bin = ((mac[offset] & 0x7f) << 24) |
              ((mac[offset + 1] & 0xff) << 16) |
              ((mac[offset + 2] & 0xff) << 8) |
              (mac[offset + 3] & 0xff);
  const mod = Math.pow(10, digits);
  const code = (bin % mod).toString().padStart(digits, '0');
  return code;
}

export async function hotp(
  secretBase32: string,
  counter: number,
  digits: number,
  algorithm: 'SHA1' | 'SHA256' | 'SHA512'
): Promise<string> {
  const msg = uint64ToBytesBE(counter);
  const key = base32Decode(secretBase32);
  const mac = await hmac(algorithm, key, msg);
  const offset = mac[mac.length - 1] & 0x0f;
  const bin = ((mac[offset] & 0x7f) << 24) |
              ((mac[offset + 1] & 0xff) << 16) |
              ((mac[offset + 2] & 0xff) << 8) |
              (mac[offset + 3] & 0xff);
  const mod = Math.pow(10, digits);
  return (bin % mod).toString().padStart(digits, '0');
}

// "123456" -> "123 456"；"12345678" -> "1234 5678"
export function formatGroups(code: string): string {
  if (code.length === 6) {
    return `${code.slice(0, 3)} ${code.slice(3)}`;
  }
  if (code.length === 8) {
    return `${code.slice(0, 4)} ${code.slice(4)}`;
  }
  return code;
}

// 计算当前周期剩余秒数
export function remainingSeconds(nowMs: number, period: number): number {
  return period - Math.floor(nowMs / 1000) % period;
}
```

- [ ] **Step 5.4: Re-run tests**

Expected: all 4 PASS.

- [ ] **Step 5.5: Commit**

```bash
git add entry/src/main/ets/services/OtpEngine.ets entry/src/ohosTest/ets/test/OtpEngine.test.ets entry/src/ohosTest/ets/test/List.test.ets
git commit -m "feat(rotor): add TOTP/HOTP engine validated against RFC 6238"
```

---

## Task 6: otpauth:// URI parser (TDD)

**Files:**
- Create: `entry/src/main/ets/utils/OtpAuthUri.ets`
- Test: `entry/src/ohosTest/ets/test/OtpAuthUri.test.ets`

- [ ] **Step 6.1: Write failing tests**

```ts
import { describe, it, expect } from '@ohos/hypium';
import { parseOtpAuth } from '../../../../main/ets/utils/OtpAuthUri';
import { OtpType } from '../../../../main/ets/model/OtpAccount';

export default function otpAuthUriTests() {
  describe('OtpAuthUri', () => {
    it('parses canonical TOTP', 0, () => {
      const r = parseOtpAuth('otpauth://totp/Google:alice@example.com?secret=JBSWY3DPEHPK3PXP&issuer=Google&period=30&digits=6&algorithm=SHA1');
      expect(r.name).assertEqual('Google');
      expect(r.note).assertEqual('alice@example.com');
      expect(r.secret).assertEqual('JBSWY3DPEHPK3PXP');
      expect(r.account.type).assertEqual(OtpType.TOTP);
      expect(r.account.period).assertEqual(30);
      expect(r.account.digits).assertEqual(6);
    });

    it('parses with only label and no issuer query', 0, () => {
      const r = parseOtpAuth('otpauth://totp/alice@example.com?secret=JBSWY3DPEHPK3PXP');
      expect(r.name).assertEqual('alice@example.com');
      expect(r.note).assertEqual('');
    });

    it('handles URL-encoded label and issuer', 0, () => {
      const r = parseOtpAuth('otpauth://totp/My%20Issuer:user%40x.com?secret=ABCDEFGH&issuer=My%20Issuer');
      expect(r.name).assertEqual('My Issuer');
      expect(r.note).assertEqual('user@x.com');
    });

    it('rejects non otpauth scheme', 0, () => {
      let threw = false;
      try { parseOtpAuth('https://example.com'); } catch (_e) { threw = true; }
      expect(threw).assertTrue();
    });
  });
}
```

Register in `List.test.ets`.

- [ ] **Step 6.2: Run, expect fail**

- [ ] **Step 6.3: Implement parser**

```ts
import { OtpAccount, OtpType, defaultAccount } from '../model/OtpAccount';

export interface ParsedOtpAuth {
  name: string;
  note: string;
  secret: string;
  account: OtpAccount;
}

export function parseOtpAuth(uri: string): ParsedOtpAuth {
  if (!uri.startsWith('otpauth://')) {
    throw new Error('not an otpauth uri');
  }
  const rest = uri.substring('otpauth://'.length);
  const slash = rest.indexOf('/');
  if (slash < 0) {
    throw new Error('missing type segment');
  }
  const typeStr = rest.substring(0, slash).toLowerCase();
  const tail = rest.substring(slash + 1);
  const qmark = tail.indexOf('?');
  const labelEnc = qmark >= 0 ? tail.substring(0, qmark) : tail;
  const queryStr = qmark >= 0 ? tail.substring(qmark + 1) : '';
  const label = decodeURIComponent(labelEnc);
  const params = parseQuery(queryStr);

  let name = '';
  let note = '';
  const colon = label.indexOf(':');
  if (colon >= 0) {
    name = label.substring(0, colon).trim();
    note = label.substring(colon + 1).trim();
  } else {
    name = label.trim();
  }
  const issuer = params['issuer'];
  if (issuer && issuer.length > 0) {
    name = issuer;
  }

  const acct = defaultAccount();
  acct.type = typeStr === 'hotp' ? OtpType.HOTP : OtpType.TOTP;
  acct.name = name;
  acct.note = note;
  acct.period = params['period'] ? parseInt(params['period']) : 30;
  acct.digits = params['digits'] ? parseInt(params['digits']) : 6;
  const algo = (params['algorithm'] || 'SHA1').toUpperCase();
  acct.algorithm = (algo === 'SHA256' || algo === 'SHA512') ? (algo as ('SHA256' | 'SHA512')) : 'SHA1';
  acct.counter = params['counter'] ? parseInt(params['counter']) : 0;

  const secret = params['secret'] || '';
  return { name, note, secret, account: acct };
}

function parseQuery(q: string): Record<string, string> {
  const out: Record<string, string> = {};
  if (!q) return out;
  for (const part of q.split('&')) {
    if (!part) continue;
    const eq = part.indexOf('=');
    const k = eq >= 0 ? part.substring(0, eq) : part;
    const v = eq >= 0 ? part.substring(eq + 1) : '';
    out[decodeURIComponent(k)] = decodeURIComponent(v);
  }
  return out;
}
```

- [ ] **Step 6.4: Re-run tests, expect PASS**

- [ ] **Step 6.5: Commit**

```bash
git add entry/src/main/ets/utils/OtpAuthUri.ets entry/src/ohosTest/ets/test/OtpAuthUri.test.ets entry/src/ohosTest/ets/test/List.test.ets
git commit -m "feat(rotor): parse otpauth:// URIs"
```

---

## Task 7: IssuerIcon mapping

**Files:**
- Create: `entry/src/main/ets/utils/IssuerIcon.ets`
- Add icon images: `entry/src/main/resources/base/media/icon_default.svg` (a simple globe; can copy from the Sketch "Aliyun" cell as PNG export)

- [ ] **Step 7.1: Export Aliyun-style default globe**

```bash
curl -sS -X POST http://localhost:31126/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","id":100,"method":"tools/call","params":{"name":"run_code","arguments":{"title":"Export default icon","script":"const sketch=require(\"sketch\");const home=sketch.find(\"#807C53E8-55A0-4ABD-9F53-031BE290A783\")[0];const aliyunRow=sketch.find(\"[name~*=Aliyun]\",home,{inclusive:true});const icon=aliyunRow.length?sketch.find(\"Group, Image, Frame, Graphic\",aliyunRow[0])[0]:null;if(icon){sketch.export(icon,{output:\"/Users/liasica/projects/deskotp/rotor-harmonyos/entry/src/main/resources/base/media\",filename:\"icon_default.png\",formats:[\"png\"],scales:\"3\"});console.log(\"ok\");}else{console.log(\"missing\");}"}}}'
```

If export missed the layer, manually export `40x40` 圆形 globe icon to `entry/src/main/resources/base/media/icon_default.png` from Sketch.

- [ ] **Step 7.2: Implement IssuerIcon**

```ts
import { Resource } from '@ohos.arkui.component';

// 内置图标映射，未命中返回默认 globe
const ICON_MAP: Record<string, Resource> = {};

export function iconForName(name: string): Resource {
  const key = (name || '').trim().toLowerCase();
  if (ICON_MAP[key]) {
    return ICON_MAP[key];
  }
  return $r('app.media.icon_default');
}
```

(Additional named icons can be added in a later increment by exporting more layers; MVP works with default fallback for every issuer.)

- [ ] **Step 7.3: Commit**

```bash
git add entry/src/main/ets/utils/IssuerIcon.ets entry/src/main/resources/base/media/icon_default.png
git commit -m "feat(rotor): default issuer icon and lookup utility"
```

---

## Task 8: SecretVault (Asset Kit)

**Files:**
- Create: `entry/src/main/ets/services/SecretVault.ets`

- [ ] **Step 8.1: Implement**

```ts
import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';

const ALIAS_PREFIX = 'otp_secret_';

function aliasFor(id: string): string {
  return ALIAS_PREFIX + id;
}

function strToUint8(s: string): Uint8Array {
  const enc = new util.TextEncoder('utf-8');
  return enc.encodeInto(s);
}

function uint8ToStr(buf: Uint8Array): string {
  const dec = util.TextDecoder.create('utf-8');
  return dec.decodeWithStream(buf);
}

export class SecretVault {
  static async put(id: string, secretBase32: string): Promise<void> {
    const attr = new Map<asset.Tag, asset.Value>();
    attr.set(asset.Tag.SECRET, strToUint8(secretBase32).buffer as object);
    attr.set(asset.Tag.ALIAS, strToUint8(aliasFor(id)).buffer as object);
    attr.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
    try {
      await asset.add(attr);
    } catch (e) {
      // Already exists -> update
      await SecretVault.update(id, secretBase32);
    }
  }

  static async update(id: string, secretBase32: string): Promise<void> {
    const query = new Map<asset.Tag, asset.Value>();
    query.set(asset.Tag.ALIAS, strToUint8(aliasFor(id)).buffer as object);
    const upd = new Map<asset.Tag, asset.Value>();
    upd.set(asset.Tag.SECRET, strToUint8(secretBase32).buffer as object);
    await asset.update(query, upd);
  }

  static async get(id: string): Promise<string> {
    const query = new Map<asset.Tag, asset.Value>();
    query.set(asset.Tag.ALIAS, strToUint8(aliasFor(id)).buffer as object);
    query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
    const arr = await asset.query(query);
    if (arr.length === 0) {
      throw new Error('secret not found: ' + id);
    }
    const sec = arr[0].get(asset.Tag.SECRET) as ArrayBuffer;
    return uint8ToStr(new Uint8Array(sec));
  }

  static async remove(id: string): Promise<void> {
    const query = new Map<asset.Tag, asset.Value>();
    query.set(asset.Tag.ALIAS, strToUint8(aliasFor(id)).buffer as object);
    try {
      await asset.remove(query);
    } catch (_e) {
      // ignore not found
    }
  }
}
```

- [ ] **Step 8.2: Commit**

```bash
git add entry/src/main/ets/services/SecretVault.ets
git commit -m "feat(rotor): SecretVault wrapping Asset Kit for OTP secrets"
```

---

## Task 9: OtpAccountStore (relationalStore)

**Files:**
- Create: `entry/src/main/ets/services/OtpAccountStore.ets`

- [ ] **Step 9.1: Implement**

```ts
import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { OtpAccount, OtpType } from '../model/OtpAccount';

const TABLE = 'otp_account';
const CREATE_SQL = `CREATE TABLE IF NOT EXISTS ${TABLE} (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  note TEXT NOT NULL DEFAULT '',
  type TEXT NOT NULL,
  period INTEGER NOT NULL DEFAULT 30,
  digits INTEGER NOT NULL DEFAULT 6,
  algorithm TEXT NOT NULL DEFAULT 'SHA1',
  counter INTEGER NOT NULL DEFAULT 0,
  iconKey TEXT NOT NULL DEFAULT '',
  orderIndex INTEGER NOT NULL DEFAULT 0,
  createdAt INTEGER NOT NULL,
  updatedAt INTEGER NOT NULL
)`;

const CONFIG: relationalStore.StoreConfig = {
  name: 'rotor.db',
  securityLevel: relationalStore.SecurityLevel.S2
};

let storePromise: Promise<relationalStore.RdbStore> | null = null;

function getStore(ctx: common.UIAbilityContext | common.Context): Promise<relationalStore.RdbStore> {
  if (!storePromise) {
    storePromise = relationalStore.getRdbStore(ctx, CONFIG).then(async (s) => {
      await s.executeSql(CREATE_SQL);
      return s;
    });
  }
  return storePromise;
}

function rowToAccount(rows: relationalStore.ResultSet): OtpAccount {
  const algo = rows.getString(rows.getColumnIndex('algorithm'));
  return {
    id: rows.getString(rows.getColumnIndex('id')),
    name: rows.getString(rows.getColumnIndex('name')),
    note: rows.getString(rows.getColumnIndex('note')),
    type: rows.getString(rows.getColumnIndex('type')) === 'hotp' ? OtpType.HOTP : OtpType.TOTP,
    period: rows.getLong(rows.getColumnIndex('period')),
    digits: rows.getLong(rows.getColumnIndex('digits')),
    algorithm: (algo === 'SHA256' || algo === 'SHA512') ? algo : 'SHA1',
    counter: rows.getLong(rows.getColumnIndex('counter')),
    iconKey: rows.getString(rows.getColumnIndex('iconKey')),
    orderIndex: rows.getLong(rows.getColumnIndex('orderIndex')),
    createdAt: rows.getLong(rows.getColumnIndex('createdAt')),
    updatedAt: rows.getLong(rows.getColumnIndex('updatedAt'))
  };
}

function toBucket(a: OtpAccount): relationalStore.ValuesBucket {
  return {
    'id': a.id, 'name': a.name, 'note': a.note, 'type': a.type,
    'period': a.period, 'digits': a.digits, 'algorithm': a.algorithm,
    'counter': a.counter, 'iconKey': a.iconKey, 'orderIndex': a.orderIndex,
    'createdAt': a.createdAt, 'updatedAt': a.updatedAt
  };
}

export class OtpAccountStore {
  static async insert(ctx: common.Context, a: OtpAccount): Promise<void> {
    const s = await getStore(ctx);
    await s.insert(TABLE, toBucket(a));
  }
  static async update(ctx: common.Context, a: OtpAccount): Promise<void> {
    const s = await getStore(ctx);
    const pred = new relationalStore.RdbPredicates(TABLE);
    pred.equalTo('id', a.id);
    await s.update(toBucket(a), pred);
  }
  static async delete(ctx: common.Context, id: string): Promise<void> {
    const s = await getStore(ctx);
    const pred = new relationalStore.RdbPredicates(TABLE);
    pred.equalTo('id', id);
    await s.delete(pred);
  }
  static async listAll(ctx: common.Context): Promise<OtpAccount[]> {
    const s = await getStore(ctx);
    const pred = new relationalStore.RdbPredicates(TABLE);
    pred.orderByAsc('orderIndex');
    const rs = await s.query(pred);
    const out: OtpAccount[] = [];
    while (rs.goToNextRow()) {
      out.push(rowToAccount(rs));
    }
    rs.close();
    return out;
  }
  static async maxOrderIndex(ctx: common.Context): Promise<number> {
    const s = await getStore(ctx);
    const rs = await s.querySql(`SELECT MAX(orderIndex) AS m FROM ${TABLE}`);
    let m = 0;
    if (rs.goToNextRow()) {
      m = rs.getLong(rs.getColumnIndex('m')) || 0;
    }
    rs.close();
    return m;
  }
}
```

- [ ] **Step 9.2: Commit**

```bash
git add entry/src/main/ets/services/OtpAccountStore.ets
git commit -m "feat(rotor): OtpAccountStore over relationalStore"
```

---

## Task 10: TickerService

**Files:**
- Create: `entry/src/main/ets/services/TickerService.ets`

- [ ] **Step 10.1: Implement**

```ts
type Listener = (nowMs: number) => void;

class Ticker {
  private timerId: number = -1;
  private listeners: Set<Listener> = new Set();

  subscribe(l: Listener): () => void {
    this.listeners.add(l);
    if (this.timerId < 0) {
      this.timerId = setInterval(() => {
        const now = Date.now();
        this.listeners.forEach(fn => fn(now));
      }, 1000);
    }
    return () => this.unsubscribe(l);
  }

  unsubscribe(l: Listener): void {
    this.listeners.delete(l);
    if (this.listeners.size === 0 && this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }
}

export const TickerService: Ticker = new Ticker();
```

- [ ] **Step 10.2: Commit**

```bash
git add entry/src/main/ets/services/TickerService.ets
git commit -m "feat(rotor): 1Hz ticker service singleton"
```

---

## Task 11: ProgressRing component

**Files:**
- Create: `entry/src/main/ets/components/ProgressRing.ets`

- [ ] **Step 11.1: Implement**

```ts
@Component
export struct ProgressRing {
  @Prop remaining: number = 30;
  @Prop period: number = 30;

  // 颜色分段：>10s 主色，3-10s 灰，<3s 红
  private color(): Resource {
    if (this.remaining < 3) {
      return $r('app.color.ring_danger');
    }
    if (this.remaining < 10) {
      return $r('app.color.ring_warn');
    }
    return $r('app.color.ring_normal');
  }

  build() {
    Stack() {
      Progress({ value: this.remaining, total: this.period, type: ProgressType.Ring })
        .width(24).height(24)
        .style({ strokeWidth: 2 })
        .color(this.color())
    }
  }
}
```

- [ ] **Step 11.2: Commit**

```bash
git add entry/src/main/ets/components/ProgressRing.ets
git commit -m "feat(rotor): ProgressRing with 3-color time segments"
```

---

## Task 12: CopyToast component

**Files:**
- Create: `entry/src/main/ets/components/CopyToast.ets`

- [ ] **Step 12.1: Implement**

```ts
@Component
export struct CopyToast {
  @Prop visible: boolean = false;

  build() {
    if (this.visible) {
      Row() {
        Text($r('app.string.toast_copied'))
          .fontColor($r('app.color.text_primary'))
          .fontSize(14)
      }
      .padding({ left: 24, right: 24, top: 10, bottom: 10 })
      .backgroundColor($r('app.color.bg_card'))
      .borderRadius(20)
      .shadow({ radius: 8, color: '#1A000000', offsetY: 2 })
    }
  }
}
```

- [ ] **Step 12.2: Commit**

```bash
git add entry/src/main/ets/components/CopyToast.ets
git commit -m "feat(rotor): CopyToast pill"
```

---

## Task 13: SearchBar component

**Files:**
- Create: `entry/src/main/ets/components/SearchBar.ets`

- [ ] **Step 13.1: Implement**

```ts
@Component
export struct SearchBar {
  @Link query: string;
  onFocusIn?: () => void;

  build() {
    Search({ value: this.query, placeholder: $r('app.string.search_placeholder') })
      .height(40)
      .backgroundColor($r('app.color.bg_card_active'))
      .borderRadius(20)
      .placeholderColor($r('app.color.text_placeholder'))
      .textFont({ size: 14 })
      .onChange((v) => { this.query = v; })
      .onClick(() => { if (this.onFocusIn) this.onFocusIn(); })
  }
}
```

- [ ] **Step 13.2: Commit**

```bash
git add entry/src/main/ets/components/SearchBar.ets
git commit -m "feat(rotor): SearchBar component"
```

---

## Task 14: Popup menus (Plus FAB)

**Files:**
- Create: `entry/src/main/ets/components/PlusMenuPopup.ets`

- [ ] **Step 14.1: Implement**

```ts
@Component
export struct PlusMenuPopup {
  onInputSecret?: () => void;
  onScanQr?: () => void;

  @Builder Item(text: Resource, onTap: () => void) {
    Text(text)
      .fontSize(16).fontColor($r('app.color.text_primary'))
      .padding({ top: 12, bottom: 12, left: 16, right: 16 })
      .width('100%')
      .onClick(() => onTap())
  }

  build() {
    Column() {
      this.Item($r('app.string.menu_input_secret'), () => this.onInputSecret && this.onInputSecret())
      Divider().color($r('app.color.divider')).height(0.5)
      this.Item($r('app.string.menu_scan_qr'), () => this.onScanQr && this.onScanQr())
    }
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(8)
    .width(160)
    .shadow({ radius: 12, color: '#1F000000', offsetY: 4 })
  }
}
```

- [ ] **Step 14.2: Commit**

```bash
git add entry/src/main/ets/components/PlusMenuPopup.ets
git commit -m "feat(rotor): PlusMenuPopup component"
```

---

## Task 15: TypeSheet component

**Files:**
- Create: `entry/src/main/ets/components/TypeSheet.ets`

- [ ] **Step 15.1: Implement**

```ts
import { OtpType } from '../model/OtpAccount';

@CustomDialog
export struct TypeSheet {
  controller: CustomDialogController;
  selected: OtpType = OtpType.TOTP;
  onSelect?: (t: OtpType) => void;

  @Builder Row(label: Resource, t: OtpType, disabled: boolean) {
    Row() {
      Text(label).fontSize(16)
        .fontColor(disabled ? $r('app.color.text_secondary') : $r('app.color.text_primary'))
        .layoutWeight(1)
      Radio({ value: t, group: 'otp_type' })
        .checked(this.selected === t)
        .enabled(!disabled)
        .onChange((on) => {
          if (on && !disabled) {
            this.selected = t;
            if (this.onSelect) this.onSelect(t);
            this.controller.close();
          }
        })
    }
    .padding({ top: 12, bottom: 12, left: 16, right: 16 })
    .opacity(disabled ? 0.5 : 1)
  }

  build() {
    Column() {
      Text($r('app.string.label_type')).fontSize(18).fontWeight(FontWeight.Bold)
        .alignSelf(ItemAlign.Start)
        .padding({ top: 16, left: 16, bottom: 8 })
      this.Row($r('app.string.type_hotp'), OtpType.HOTP, true)
      this.Row($r('app.string.type_totp'), OtpType.TOTP, false)
      Button($r('app.string.btn_cancel'))
        .backgroundColor(Color.Transparent)
        .fontColor($r('app.color.accent_blue'))
        .width('100%').height(48)
        .onClick(() => this.controller.close())
    }
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius({ topLeft: 16, topRight: 16 })
    .width('100%')
  }
}
```

- [ ] **Step 15.2: Commit**

```bash
git add entry/src/main/ets/components/TypeSheet.ets
git commit -m "feat(rotor): TypeSheet bottom dialog"
```

---

## Task 16: DeleteConfirmDialog component

**Files:**
- Create: `entry/src/main/ets/components/DeleteConfirmDialog.ets`

- [ ] **Step 16.1: Implement**

```ts
@CustomDialog
export struct DeleteConfirmDialog {
  controller: CustomDialogController;
  name: string = '';
  onConfirm?: () => void;

  build() {
    Column() {
      Text(`是否要删除 ${this.name}？`)
        .fontSize(16)
        .fontColor($r('app.color.text_primary'))
        .padding({ top: 24, bottom: 24 })
      Row() {
        Button($r('app.string.btn_cancel'))
          .backgroundColor(Color.Transparent)
          .fontColor($r('app.color.accent_blue'))
          .layoutWeight(1).height(48)
          .onClick(() => this.controller.close())
        Divider().vertical(true).strokeWidth(0.5).color($r('app.color.divider')).height(20)
        Button($r('app.string.btn_delete'))
          .backgroundColor(Color.Transparent)
          .fontColor($r('app.color.accent_red'))
          .layoutWeight(1).height(48)
          .onClick(() => {
            this.controller.close();
            if (this.onConfirm) this.onConfirm();
          })
      }
    }
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius({ topLeft: 16, topRight: 16 })
    .width('100%')
  }
}
```

- [ ] **Step 16.2: Commit**

```bash
git add entry/src/main/ets/components/DeleteConfirmDialog.ets
git commit -m "feat(rotor): bottom delete confirmation dialog"
```

---

## Task 17: OtpItem card component

**Files:**
- Create: `entry/src/main/ets/components/OtpItem.ets`

- [ ] **Step 17.1: Implement**

```ts
import { ProgressRing } from './ProgressRing';
import { OtpAccount } from '../model/OtpAccount';
import { iconForName } from '../utils/IssuerIcon';
import { formatGroups } from '../services/OtpEngine';

@Component
export struct OtpItem {
  @Prop account: OtpAccount;
  @Prop code: string = '------';
  @Prop remaining: number = 30;
  @Prop highlighted: boolean = false;
  onTap?: () => void;

  private codeColor(): Resource {
    return this.remaining < 3 ? $r('app.color.accent_red') : $r('app.color.text_primary');
  }

  build() {
    Column() {
      Row() {
        Image(iconForName(this.account.name)).width(28).height(28).borderRadius(14)
        Text(this.account.name).fontSize(18).fontWeight(FontWeight.Bold).margin({ left: 8 })
          .fontColor($r('app.color.text_primary'))
      }
      .alignItems(VerticalAlign.Center)
      Row() {
        Text(formatGroups(this.code))
          .fontSize(32)
          .fontWeight(FontWeight.Bolder)
          .fontColor(this.codeColor())
          .layoutWeight(1)
        ProgressRing({ remaining: this.remaining, period: this.account.period })
      }
      .alignItems(VerticalAlign.Center)
      .margin({ top: 8 })
      Text(this.account.note)
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: 4 })
    }
    .padding(16)
    .backgroundColor(this.highlighted ? $r('app.color.bg_card_active') : $r('app.color.bg_card'))
    .borderRadius(16)
    .width('100%')
    .onClick(() => { if (this.onTap) this.onTap(); })
  }
}
```

- [ ] **Step 17.2: Commit**

```bash
git add entry/src/main/ets/components/OtpItem.ets
git commit -m "feat(rotor): OtpItem list card"
```

---

## Task 18: EditPage

**Files:**
- Create: `entry/src/main/ets/pages/EditPage.ets`

- [ ] **Step 18.1: Implement**

```ts
import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { OtpAccount, OtpType, defaultAccount } from '../model/OtpAccount';
import { OtpAccountStore } from '../services/OtpAccountStore';
import { SecretVault } from '../services/SecretVault';
import { isValidBase32, base32Normalize } from '../utils/Base32';
import { TypeSheet } from '../components/TypeSheet';
import { promptAction } from '@kit.ArkUI';

interface EditParams {
  id?: string;
  prefilled?: OtpAccount;
  prefilledSecret?: string;
}

@Entry
@Component
struct EditPage {
  @State account: OtpAccount = defaultAccount();
  @State secret: string = '';
  @State isEdit: boolean = false;
  @State error: string = '';

  typeDialog: CustomDialogController = new CustomDialogController({
    builder: TypeSheet({
      selected: this.account.type,
      onSelect: (t: OtpType) => { this.account.type = t; }
    }),
    alignment: DialogAlignment.Bottom,
    customStyle: true
  });

  aboutToAppear(): void {
    const params = router.getParams() as EditParams;
    if (params && params.id) {
      this.isEdit = true;
      this.account = params.prefilled || defaultAccount();
      SecretVault.get(params.id).then((s) => { this.secret = s; }).catch(() => { this.secret = ''; });
    } else if (params && params.prefilled) {
      this.account = params.prefilled;
      this.secret = params.prefilledSecret || '';
    }
  }

  private valid(): boolean {
    if (!this.account.name || this.account.name.length === 0) return false;
    if (!isValidBase32(this.secret)) return false;
    return true;
  }

  private async save(): Promise<void> {
    if (!this.valid()) {
      this.error = !this.account.name ? '请填写名称' : '秘钥格式不正确';
      promptAction.showToast({ message: this.error });
      return;
    }
    const ctx = getContext(this) as common.UIAbilityContext;
    const now = Date.now();
    if (!this.isEdit) {
      this.account.id = util.generateRandomUUID(false);
      this.account.createdAt = now;
      this.account.orderIndex = (await OtpAccountStore.maxOrderIndex(ctx)) + 1;
    }
    this.account.updatedAt = now;
    await SecretVault.put(this.account.id, base32Normalize(this.secret));
    if (this.isEdit) {
      await OtpAccountStore.update(ctx, this.account);
    } else {
      await OtpAccountStore.insert(ctx, this.account);
    }
    router.back();
  }

  @Builder Field(label: Resource, value: string, onChange: (v: string) => void, placeholder: string) {
    Row() {
      Text(label).fontSize(14).fontColor($r('app.color.text_secondary')).width(56)
      TextInput({ text: value, placeholder })
        .fontColor($r('app.color.text_primary'))
        .placeholderColor($r('app.color.text_placeholder'))
        .backgroundColor(Color.Transparent)
        .layoutWeight(1)
        .onChange(onChange)
    }
    .padding({ top: 12, bottom: 12, left: 16, right: 16 })
  }

  build() {
    Column() {
      Row() {
        Text('×').fontSize(24).fontColor($r('app.color.text_primary'))
          .onClick(() => router.back())
        Text(this.isEdit ? $r('app.string.edit_title') : $r('app.string.add_title'))
          .fontSize(18).margin({ left: 12 }).layoutWeight(1)
          .fontColor($r('app.color.text_primary'))
        Text('✓').fontSize(22)
          .fontColor(this.valid() ? $r('app.color.accent_blue') : $r('app.color.text_placeholder'))
          .onClick(() => this.save())
      }.padding(16).width('100%')

      Column() {
        Image($r('app.media.icon_default')).width(64).height(64).borderRadius(32).margin({ top: 24, bottom: 24 })
      }

      Column() {
        this.Field($r('app.string.label_name'), this.account.name, (v) => { this.account.name = v; }, '')
        Divider().color($r('app.color.divider'))
        this.Field($r('app.string.label_note'), this.account.note, (v) => { this.account.note = v; }, '')
      }
      .backgroundColor($r('app.color.bg_card'))
      .borderRadius(16)
      .margin({ left: 16, right: 16, bottom: 12 })

      Column() {
        this.Field($r('app.string.label_secret'), this.secret, (v) => { this.secret = v; }, '')
      }
      .backgroundColor($r('app.color.bg_card'))
      .borderRadius(16)
      .margin({ left: 16, right: 16, bottom: 12 })

      Column() {
        Row() {
          Text($r('app.string.label_type')).fontSize(14).fontColor($r('app.color.text_secondary')).width(56)
          Text(this.account.type === OtpType.TOTP ? $r('app.string.type_totp') : $r('app.string.type_hotp'))
            .fontColor($r('app.color.text_placeholder')).layoutWeight(1).textAlign(TextAlign.End)
          Text('›').fontColor($r('app.color.text_placeholder')).margin({ left: 8 })
        }
        .padding({ top: 12, bottom: 12, left: 16, right: 16 })
        .onClick(() => this.typeDialog.open())
      }
      .backgroundColor($r('app.color.bg_card'))
      .borderRadius(16)
      .margin({ left: 16, right: 16 })
    }
    .width('100%').height('100%')
    .backgroundColor($r('app.color.bg_app'))
  }
}
```

- [ ] **Step 18.2: Commit**

```bash
git add entry/src/main/ets/pages/EditPage.ets
git commit -m "feat(rotor): add/edit page with TypeSheet"
```

---

## Task 19: ScanPage

**Files:**
- Create: `entry/src/main/ets/pages/ScanPage.ets`

- [ ] **Step 19.1: Implement**

```ts
import { router } from '@kit.ArkUI';
import { scanCore, scanBarcode } from '@kit.ScanKit';
import { abilityAccessCtrl, common, PermissionRequestResult, Permissions } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { parseOtpAuth } from '../utils/OtpAuthUri';

@Entry
@Component
struct ScanPage {
  aboutToAppear(): void {
    this.requestAndScan();
  }

  private async requestAndScan(): Promise<void> {
    const ctx = getContext(this) as common.UIAbilityContext;
    const atManager = abilityAccessCtrl.createAtManager();
    const perms: Permissions[] = ['ohos.permission.CAMERA'];
    try {
      const r: PermissionRequestResult = await atManager.requestPermissionsFromUser(ctx, perms);
      const granted = r.authResults && r.authResults[0] === 0;
      if (!granted) {
        promptAction.showToast({ message: '需要相机权限' });
        router.back();
        return;
      }
      const opts: scanBarcode.ScanOptions = {
        scanTypes: [scanCore.ScanType.QR_CODE],
        enableMultiMode: false,
        enableAlbum: true
      };
      const result = await scanBarcode.startScanForResult(ctx, opts);
      const text = result.originalValue || '';
      try {
        const parsed = parseOtpAuth(text);
        router.replaceUrl({
          url: 'pages/EditPage',
          params: { prefilled: parsed.account, prefilledSecret: parsed.secret }
        });
      } catch (_e) {
        promptAction.showToast({ message: '未识别的二维码' });
        router.back();
      }
    } catch (_e) {
      router.back();
    }
  }

  build() {
    Column() {
      Text('正在打开相机…').fontColor($r('app.color.text_primary'))
    }.width('100%').height('100%').justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.bg_app'))
  }
}
```

- [ ] **Step 19.2: Commit**

```bash
git add entry/src/main/ets/pages/ScanPage.ets
git commit -m "feat(rotor): QR scan page integrating ScanKit"
```

---

## Task 20: Index page (replace stub) — list, search, swipe, FAB, copy

**Files:**
- Replace: `entry/src/main/ets/pages/Index.ets`

- [ ] **Step 20.1: Implement Index**

```ts
import { router } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { OtpAccount } from '../model/OtpAccount';
import { OtpAccountStore } from '../services/OtpAccountStore';
import { SecretVault } from '../services/SecretVault';
import { totp, remainingSeconds } from '../services/OtpEngine';
import { TickerService } from '../services/TickerService';
import { OtpItem } from '../components/OtpItem';
import { SearchBar } from '../components/SearchBar';
import { CopyToast } from '../components/CopyToast';
import { PlusMenuPopup } from '../components/PlusMenuPopup';
import { DeleteConfirmDialog } from '../components/DeleteConfirmDialog';

interface CodeState {
  code: string;
  remaining: number;
}

@Entry
@Component
struct Index {
  @State accounts: OtpAccount[] = [];
  @State codes: Record<string, CodeState> = {};
  @State secrets: Record<string, string> = {};
  @State query: string = '';
  @State activeId: string = '';
  @State toastVisible: boolean = false;
  @State plusOpen: boolean = false;
  @State pendingDelete: OtpAccount | null = null;
  private unsubTick: (() => void) | null = null;

  deleteDialog: CustomDialogController = new CustomDialogController({
    builder: DeleteConfirmDialog({
      name: '',
      onConfirm: () => this.confirmDelete()
    }),
    alignment: DialogAlignment.Bottom,
    customStyle: true
  });

  aboutToAppear(): void {
    this.refresh();
    this.unsubTick = TickerService.subscribe((now) => this.tick(now));
  }

  aboutToDisappear(): void {
    if (this.unsubTick) this.unsubTick();
  }

  onPageShow(): void {
    this.refresh();
  }

  private async refresh(): Promise<void> {
    const ctx = getContext(this) as common.UIAbilityContext;
    this.accounts = await OtpAccountStore.listAll(ctx);
    for (const a of this.accounts) {
      if (!this.secrets[a.id]) {
        try {
          this.secrets[a.id] = await SecretVault.get(a.id);
        } catch (_e) {
          this.secrets[a.id] = '';
        }
      }
    }
    await this.tick(Date.now());
  }

  private async tick(now: number): Promise<void> {
    const next: Record<string, CodeState> = {};
    for (const a of this.accounts) {
      const remaining = remainingSeconds(now, a.period);
      const prev = this.codes[a.id];
      let code = prev ? prev.code : '------';
      const sec = this.secrets[a.id];
      if (sec && (!prev || remaining === a.period || prev.code === '------')) {
        try {
          code = await totp(sec, now, a.period, a.digits, a.algorithm);
        } catch (_e) { code = '------'; }
      }
      next[a.id] = { code, remaining };
    }
    this.codes = next;
  }

  private filtered(): OtpAccount[] {
    if (!this.query) return this.accounts;
    const q = this.query.toLowerCase();
    return this.accounts.filter(a =>
      a.name.toLowerCase().includes(q) || a.note.toLowerCase().includes(q));
  }

  private async copy(a: OtpAccount): Promise<void> {
    const c = this.codes[a.id];
    if (!c) return;
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, c.code);
    await pasteboard.getSystemPasteboard().setData(data);
    this.activeId = a.id;
    this.toastVisible = true;
    setTimeout(() => { this.toastVisible = false; }, 1500);
  }

  private askDelete(a: OtpAccount): void {
    this.pendingDelete = a;
    this.deleteDialog = new CustomDialogController({
      builder: DeleteConfirmDialog({
        name: a.name,
        onConfirm: () => this.confirmDelete()
      }),
      alignment: DialogAlignment.Bottom,
      customStyle: true
    });
    this.deleteDialog.open();
  }

  private async confirmDelete(): Promise<void> {
    if (!this.pendingDelete) return;
    const ctx = getContext(this) as common.UIAbilityContext;
    const id = this.pendingDelete.id;
    await SecretVault.remove(id);
    await OtpAccountStore.delete(ctx, id);
    this.pendingDelete = null;
    this.refresh();
  }

  private edit(a: OtpAccount): void {
    router.pushUrl({ url: 'pages/EditPage', params: { id: a.id, prefilled: a } });
  }

  @Builder SwipeStart(a: OtpAccount) {
    Row() {
      Stack() {
        Image($r('app.media.icon_default')).width(20).height(20)
      }
      .backgroundColor($r('app.color.bg_card'))
      .width(56).height('80%').borderRadius(28)
      .onClick(() => this.edit(a))
    }
  }

  @Builder SwipeEnd(a: OtpAccount) {
    Row() {
      Text('🗑').fontSize(20).fontColor(Color.White)
    }
    .backgroundColor($r('app.color.accent_red'))
    .width(56).height('80%').borderRadius(28).justifyContent(FlexAlign.Center)
    .onClick(() => this.askDelete(a))
  }

  build() {
    Stack() {
      Column() {
        Row() {
          Blank().layoutWeight(1)
          Text('+').fontSize(20).fontColor($r('app.color.text_primary'))
            .opacity(0)
        }.padding({ top: 12, left: 16, right: 16 }).width('100%')

        SearchBar({ query: $query }).margin({ left: 16, right: 16, top: 4, bottom: 8 })

        List({ space: 12 }) {
          ForEach(this.filtered(), (a: OtpAccount) => {
            ListItem() {
              OtpItem({
                account: a,
                code: this.codes[a.id] ? this.codes[a.id].code : '------',
                remaining: this.codes[a.id] ? this.codes[a.id].remaining : a.period,
                highlighted: this.activeId === a.id,
                onTap: () => this.copy(a)
              })
            }
            .swipeAction({
              start: { builder: () => this.SwipeStart(a) },
              end: { builder: () => this.SwipeEnd(a) }
            })
          }, (a: OtpAccount) => a.id)
        }
        .layoutWeight(1)
        .padding({ left: 16, right: 16, bottom: 16 })

        if (this.accounts.length === 0) {
          Column() {
            Text($r('app.string.empty_hint'))
              .fontColor($r('app.color.text_secondary')).fontSize(14)
          }.layoutWeight(1).justifyContent(FlexAlign.Center).width('100%')
        }
      }.width('100%').height('100%').backgroundColor($r('app.color.bg_app'))

      // FAB + popup
      Column() {
        if (this.plusOpen) {
          PlusMenuPopup({
            onInputSecret: () => {
              this.plusOpen = false;
              router.pushUrl({ url: 'pages/EditPage' });
            },
            onScanQr: () => {
              this.plusOpen = false;
              router.pushUrl({ url: 'pages/ScanPage' });
            }
          })
            .margin({ bottom: 8, right: 16 })
        }
        Button('+')
          .width(56).height(56).borderRadius(28)
          .backgroundColor($r('app.color.accent_blue'))
          .fontColor(Color.White).fontSize(28)
          .onClick(() => { this.plusOpen = !this.plusOpen; })
      }
      .position({ right: 16, bottom: 16 })
      .alignItems(HorizontalAlign.End)

      // Toast
      if (this.toastVisible) {
        Column() {
          CopyToast({ visible: this.toastVisible })
        }.position({ bottom: 100 }).width('100%').alignItems(HorizontalAlign.Center)
      }
    }
    .width('100%').height('100%')
  }
}
```

- [ ] **Step 20.2: Build**

```bash
hvigorw clean && hvigorw assembleHap --mode module -p product=default -p buildMode=debug
```

Expected: BUILD SUCCESSFUL.

- [ ] **Step 20.3: Commit**

```bash
git add entry/src/main/ets/pages/Index.ets
git commit -m "feat(rotor): wire Index page with list, search, swipe and FAB"
```

---

## Task 21: Smoke test on device/emulator

**Files:** none (manual verification)

- [ ] **Step 21.1: Install on emulator/device via DevEco Studio**

Run the app from DevEco. Smoke checklist:

1. App launches to empty state with hint text.
2. FAB → "输入设置密钥" → fill name "Google", note "alice@gmail.com", secret `JBSWY3DPEHPK3PXP`, save → returns to list with one card.
3. Card shows 6-digit code; ring decreases each second; code refreshes at 30s boundary.
4. Tap card → "已复制" toast appears; system clipboard contains the 6 digits.
5. Right-swipe card → tap edit → modify name → save → list updates.
6. Left-swipe card → tap delete icon → confirm in bottom dialog → card removed.
7. FAB → "扫描二维码" → grant camera → scan a `otpauth://totp/...` QR → arrives at edit page prefilled → save → appears in list.
8. Toggle system theme: list/cards/dialog colors flip correctly.
9. Search: type partial name → list filters; clear → restores.

- [ ] **Step 21.2: Run unit tests**

In DevEco Studio: right-click `ohosTest` → Run 'All Tests'. Expected: Base32, OtpEngine, OtpAuthUri suites all green.

- [ ] **Step 21.3: Final commit (if any tweaks)**

```bash
git status
# fix anything found during smoke
git add -A
git commit -m "chore(rotor): smoke fixes from device verification"
```

---

## Self-review summary

- All spec sections (§1-§11) map to tasks: model (T2), Asset Kit (T8), RDB (T9), TOTP (T4-T5), URI (T6), UI components (T11-T17), pages (T18-T20), resources/permissions/icon (T1), tests (T3, T5, T6), smoke (T21).
- No placeholders. Each step has either concrete code, exact command, or explicit expected result.
- API surface consistency verified: `OtpAccount` fields, `SecretVault.{put,get,remove}`, `OtpAccountStore.{insert,update,delete,listAll,maxOrderIndex}`, `totp(secret, nowMs, period, digits, algo)`, `formatGroups`, `parseOtpAuth` shape.
