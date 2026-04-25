# Rotor Authenticator 设计文档

- 项目：rotor-harmonyos（HarmonyOS NEXT，API 23，ArkTS）
- 包名：`com.liasica.rotor`
- 范围：MVP + 扫码（B 方案）
- 设计稿：`Authenticator 1217.sketch`（页面"设计"）
- 日期：2026-04-25

## 1. 目标与范围

实现一个本地 TOTP 验证码 App，对标 Google Authenticator。本轮交付：

**包含**
- 首页 OTP 列表（图标、名称、6 位验证码、备注、30s 进度环）
- 顶部搜索（按名称/描述模糊匹配）
- 添加账号：手动输入密钥、扫描二维码（otpauth://）
- 编辑账号：名称/描述/密钥/类型
- 删除账号（左滑 + 底部确认弹窗）
- 编辑账号入口（右滑暴露蓝色编辑按钮）
- 点击验证码复制到剪贴板，显示"已复制" toast
- 深浅主题跟随系统
- 应用图标（采用设计稿 appicon）

**MVP 中暂不显示的设计入口**
- 首页右上"…"按钮：MVP 不渲染图标（隐藏入口），组件代码保留以便二期接入

**不包含（推迟到后续阶段）**
- 扫码导入：Google Authenticator 迁移协议（`otpauth-migration://`，protobuf）
- 导出（多选 + 加密备份）
- 关于页正式内容
- HOTP（基于计数器）—— UI 槽位保留并 disable
- 国际化英文 —— 字符串结构保留 `string:` 引用，本轮仅中文资源

## 2. 总体架构

### 2.1 模块划分

```
entry/src/main/ets/
├── pages/
│   ├── Index.ets              # 首页：列表、搜索、滑动操作、FAB、菜单、Toast
│   ├── EditPage.ets           # 添加 / 编辑表单
│   └── ScanPage.ets           # 扫描二维码
├── components/
│   ├── OtpItem.ets            # 单条卡片
│   ├── ProgressRing.ets       # 30s 倒计时圆环
│   ├── SearchBar.ets          # 搜索框
│   ├── PlusMenuPopup.ets      # 加号弹出菜单（输入设置密钥 / 扫描二维码）
│   ├── MoreMenuPopup.ets      # 右上"…"菜单组件（MVP 不渲染入口图标；组件保留备用）
│   ├── TypeSheet.ets          # 类型半屏（基于计数器 / 基于时间）
│   ├── DeleteConfirmDialog.ets# 底部"是否要删除 X？"
│   └── CopyToast.ets          # "已复制" 浮层
├── services/
│   ├── OtpAccountStore.ets    # 元数据 CRUD（关系型数据库）
│   ├── SecretVault.ets        # 密钥读写（Asset Kit）
│   ├── OtpEngine.ets          # TOTP 计算（RFC 6238）
│   └── TickerService.ets      # 单例秒级 tick，订阅刷新
├── utils/
│   ├── OtpAuthUri.ets         # 解析 otpauth:// URI
│   ├── Base32.ets             # RFC 4648 base32 解码
│   ├── HmacSha1.ets           # 通过 cryptoFramework 计算 HMAC-SHA1
│   └── IssuerIcon.ets         # issuer → 内置图标资源映射
└── model/
    ├── OtpAccount.ets         # 元数据接口
    └── OtpType.ets            # 枚举：TOTP / HOTP（HOTP 仅占位）
```

### 2.2 关键边界

| 边界 | 决策 | 理由 |
|---|---|---|
| 密钥存储 | `@kit.AssetStoreKit`，alias = `otp_secret_<id>` | 系统级凭据存储，与设备锁绑定，禁止落库 |
| 元数据存储 | `@kit.ArkData` 关系型数据库（SQLite） | 列表查询/排序/搜索 |
| 加密 | 不自实现；密钥读写均经 Asset Kit | 避免造轮子 |
| TOTP 算法 | HMAC-SHA1 / 30s / 6 位（RFC 6238 默认） | 与 Google Authenticator 兼容 |
| HMAC 实现 | `@kit.CryptoArchitectureKit`（cryptoFramework） | 系统库 |
| 二维码扫描 | `@kit.ScanKit` 的 `customScan` | HarmonyOS 官方扫码 |
| 主题 | 资源引用 + ColorMode 跟随系统 | 颜色不写死 |

### 2.3 数据模型

```ts
// model/OtpAccount.ets
export interface OtpAccount {
  id: string;          // uuid
  name: string;        // issuer 名称（卡片主标题，如 "Google"）
  note: string;        // 副标题（如账号邮箱），可空
  type: OtpType;       // MVP: 仅 TOTP
  period: number;      // 默认 30
  digits: number;      // 默认 6
  algorithm: 'SHA1' | 'SHA256' | 'SHA512'; // 默认 SHA1
  counter?: number;    // HOTP 占位，MVP 不使用
  iconKey?: string;    // 命中内置图标库时填写，否则 undefined
  orderIndex: number;  // 列表排序，新增 = max+1
  createdAt: number;
  updatedAt: number;
}
```

RDB 表 `otp_account` 字段同上（`secret` **不存**）。索引：`orderIndex`、`name`。

```ts
// services/SecretVault.ets
put(id: string, secretBase32: string): Promise<void>
get(id: string): Promise<string>          // 返回 base32
remove(id: string): Promise<void>
```

## 3. 用户流程

### 3.1 添加（手动）
1. 首页 FAB 加号 → 弹出 `PlusMenuPopup` → 选"输入设置密钥"
2. 进入 `EditPage`（mode=create，无预填）
3. 用户填名称 / 描述 / 秘钥 / 类型（MVP 锁定"基于时间"）
4. 顶部 ✓ 校验通过后：
   - `accountId = uuid()`
   - `SecretVault.put(accountId, normalizedSecret)`
   - `OtpAccountStore.insert(meta)`
   - `router.back()`，首页 `onPageShow` 重新查询并显示

### 3.2 添加（扫码）
1. 首页 FAB → 选"扫描二维码"
2. 申请相机权限（首次）→ 进入 `ScanPage`
3. 扫到 `otpauth://totp/Issuer:label?secret=...&issuer=...&period=30&digits=6&algorithm=SHA1`
4. `OtpAuthUri.parse()` → 跳 `EditPage`（mode=create，预填字段）
5. 用户确认 ✓ 后落库（同手动流程的步骤 4）

### 3.3 读取/刷新验证码
- `Index.aboutToAppear()`：`OtpAccountStore.listAll()` 拿元数据
- 内存 `Map<id, secret>`：首次显示时按需 `SecretVault.get()`，后续命中缓存
- `TickerService` 每 1s 触发：
  - `remaining = period - (Math.floor(Date.now()/1000) % period)`
  - 当 `remaining === period`（跨周期）：重算每条 `code = OtpEngine.totp(secret, now)`
  - 否则只更新各 `ProgressRing` 显示

### 3.4 复制
- 点击卡片任意位置 → `pasteboard.setData(code)` → 显示 `CopyToast`（约 1.5s 自动消失）
- 同时高亮当前条目（深色卡片样式，与设计稿一致），下次点击其他条目时切换

### 3.5 编辑
- 列表 item **右滑** 暴露蓝色"编辑"按钮（`ListItem.swipeAction.start`）
- 点击 → `EditPage`（mode=edit，预填全部字段；秘钥从 Asset Kit 取）
- 保存：更新 RDB；若秘钥改了，覆盖 Asset Kit 同 alias

### 3.6 删除
- 列表 item **左滑** 暴露红色"删除"按钮（`ListItem.swipeAction.end`）
- 点击 → `DeleteConfirmDialog`（底部，文案"是否要删除 \<name\>？"）
- 确认 → `SecretVault.remove(id)` → `OtpAccountStore.delete(id)` → 列表移除

### 3.7 搜索
- 顶部 `SearchBar` 点击聚焦 → 进入搜索激活态：列表加灰色蒙层、底部弹起系统键盘
- 输入时增量过滤（`name LIKE %q% OR note LIKE %q%`，本地内存过滤即可）
- 返回箭头退出搜索态

## 4. UI 规范

### 4.1 颜色 token（资源引用，深浅各一套）
| 名称 | light | dark | 用途 |
|---|---|---|---|
| `bg_app` | #F2F3F5 | #000000 | 页面底色 |
| `bg_card` | #FFFFFF | #1C1C1E | 卡片底 |
| `bg_card_active` | #E5E5EA | #2C2C2E | 选中卡片底（已复制态） |
| `text_primary` | #000000 | #FFFFFF | 名称、验证码 |
| `text_secondary` | #8E8E93 | #8E8E93 | 描述/备注 |
| `accent_blue` | #2772FF | #2772FF | FAB、对话框确认、编辑按钮 |
| `accent_red` | #FF3B30 | #FF3B30 | 即将过期验证码、删除按钮 |
| `ring_normal` | text_primary | text_primary | 倒计时 >10s |
| `ring_warn` | #C7C7CC | #5A5A5C | 倒计时 3-10s |
| `ring_danger` | accent_red | accent_red | 倒计时 <3s |

颜色值若与系统资源（`$r('sys.color.…')`）匹配则优先用系统资源。

### 4.2 字体
- 验证码：粗体，约 32sp，字间距加大，6 位中间空格分隔（`033 577`）
- 名称：18sp 粗体
- 描述：14sp 常规
- 标签（"名称"/"描述"/"秘钥"/"类型"）：14sp 灰

### 4.3 卡片
- 圆角 16vp
- 内边距 16vp
- 卡片间距 12vp
- 阴影：light 模式淡阴影；dark 模式无阴影

### 4.4 进度环
- 直径 24vp，描边 2vp
- 起始 12 点钟方向，顺时针绘制 `remaining/period` 比例的圆弧
- 颜色按 4.1 三段切换

## 5. TOTP 算法实现

`OtpEngine.totp(secretBase32, nowMs, period=30, digits=6, algo='SHA1')`：

1. `T = floor(nowMs / 1000 / period)`
2. `msg = 8 字节大端整数(T)`
3. `key = base32Decode(secretBase32)`
4. `mac = HMAC(algo, key, msg)`（通过 `cryptoFramework` 的 `Mac`）
5. `offset = mac[mac.length - 1] & 0x0f`
6. `bin = ((mac[offset] & 0x7f) << 24) | (mac[offset+1] << 16) | (mac[offset+2] << 8) | mac[offset+3]`
7. `code = (bin % 10^digits).toString().padStart(digits, '0')`
8. 显示时插入空格：`code.slice(0, digits/2) + ' ' + code.slice(digits/2)`

Base32 解码遵循 RFC 4648（容忍空格、连字符、小写、可选 `=` padding）。

## 6. URI 解析

`otpauth://totp/Issuer:label?secret=BASE32&issuer=Issuer&period=30&digits=6&algorithm=SHA1`

字段映射：
- 路径段（去掉 `Issuer:` 前缀后剩余）→ `note`（label）
- 路径段中冒号前 或 query `issuer` → `name`
- `secret` → 走 SecretVault
- `period` / `digits` / `algorithm` → 同字段（缺省取默认）
- 不识别的参数忽略（前向兼容）

## 7. 错误处理与边界

| 场景 | 处理 |
|---|---|
| 秘钥含非 base32 字符 | 表单不允许保存，下方红字提示 |
| Asset Kit 写入失败 | 不写 RDB，弹 toast 错误，让用户重试 |
| Asset Kit 取秘钥失败 | 卡片显示 `------`，仍可右滑编辑修复 |
| 扫码非 otpauth:// | 留在扫描页提示"未识别"，不退出 |
| 时间偏移过大 | 不做服务器对时；用户感知到偏差由系统时间负责 |
| 跨周期 tick 抖动 | 以系统时间计算，UI 仅基于 `Date.now()` 不累计 |

## 8. 权限

`entry/src/main/module.json5`：
- `ohos.permission.CAMERA`（扫码）—— 用户授权前不打开扫码页
- 其他无网络/存储权限（Asset Kit 与 RDB 沙箱内）

## 9. 依赖

- 系统 Kit：`@kit.AssetStoreKit`、`@kit.ArkData`、`@kit.CryptoArchitectureKit`、`@kit.ScanKit`、`@ohos.pasteboard`、`@ohos.app.ability.ConfigurationConstant`
- 第三方依赖：无（uuid 自实现 4 位 + 时间戳；或用 `@ohos.util.UUID` 系统能力）

## 10. 测试

`entry/src/test/`（HarmonyOS Hypium）：
- `OtpEngine.test.ets`：用 RFC 6238 标准测试向量校验 6 位输出
- `Base32.test.ets`：常见输入/边界/非法字符
- `OtpAuthUri.test.ets`：标准/省略参数/含中文 issuer

UI 单测不在 MVP 范围；功能验证以真机为准。

## 11. 开放/后续

- 列表排序：MVP 默认按 `orderIndex` 升序，新增追加；不支持手动拖拽（设计稿无此入口）
- 图标库：内置一组常见 issuer 图标（设计稿出现的 Sony / Google / Discord / Aliyun + 一批），命中策略 = `name.toLowerCase()` 精确匹配；未命中显示默认地球图标（与设计稿"Aliyun"行的灰底地球一致）
- 第二阶段候选：HOTP、Google Migration 导入、加密备份导出、关于页
