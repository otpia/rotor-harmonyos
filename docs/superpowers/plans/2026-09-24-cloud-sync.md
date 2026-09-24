# Rotor 云同步实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 账号与密钥经华为云空间在同一华为账号的设备间同步，首页右上角显示同步状态。

**Architecture:** 密钥从 Asset Kit 迁入 `rotor.db` 的 `OtpAccount.secret` 列，旧表 `otp_account` 的数据搬进端云同步结构的新表；`CloudSyncService` 单例封装 `setDistributedTables`、`cloudSync`、云端变更订阅与网络监听；首页标题栏菜单图标与新的「云同步」二级页订阅其状态。

**Tech Stack:** ArkTS、ArkUI、UI Design Kit（HdsNavigation / HdsNavDestination）、ArkData relationalStore 与 preferences、Network Kit、Asset Store Kit（仅迁移读取）。

**Spec:** `docs/superpowers/specs/2026-09-24-cloud-sync-design.md`

## Global Constraints

- `compatibleSdkVersion` 与 `targetSdkVersion` 为 26.0.0，不做低版本兼容分支
- 库名 `rotor.db` 对应 AGC 容器 `rotor`，表名 `OtpAccount` 对应同名 AGC 数据类型（只允许字母和数字、以字母开头），对应关系不可改
- 端云同步表所有列不带 `NOT NULL`，主键为 UUID 文本
- 颜色、字号、圆角用 `sys.color.*` / `sys.float.*`，图标用 `sys.symbol.*`，文案进 `string.json` 中英文各一份
- 弹窗一律系统能力，弹窗与半模态 `ULTRA_THICK` 材质，Toast `THICK`
- ArkTS 严格模式：可能抛异常的调用包 try/catch，rethrow 用 `throw new Error(String(e))`
- 不写单元测试；每个任务以 hvigor 编译通过加模拟器实测作为验证，完成后单独提交
- 共用真机上另有会话在调试，本计划只在模拟器 `127.0.0.1:5555` 上安装验证，所有 hdc 命令带 `-t 127.0.0.1:5555`

---

### Task 1: 密钥迁入数据库

**Files:**
- Modify: `entry/src/main/ets/model/OtpAccount.ets`
- Modify: `entry/src/main/ets/services/OtpAccountStore.ets`
- Delete: `entry/src/main/ets/services/SecretVault.ets`
- Modify: `entry/src/main/ets/services/AccountDedup.ets`、`ScanService.ets`、`BackupImporter.ets`
- Modify: `entry/src/main/ets/pages/Index.ets`、`EditPage.ets`、`ManagePage.ets`

**Interfaces:**
- Produces: `OtpAccount.secret: string`；`export const ACCOUNT_TABLE = 'OtpAccount'`；`OtpAccountStore.store(ctx: common.Context): Promise<relationalStore.RdbStore>`

- [ ] **Step 1:** 模型加 `secret`，`defaultAccount` 置 `''`，`cloneAccount` 复制
- [ ] **Step 2:** `OtpAccountStore` 改为规格 4.1 的建表语句、`securityLevel: S3`；`rowToAccount` 每列用 `isColumnNull` 兜底；`toBucket` 带 `secret`；暴露 `store(ctx)`
- [ ] **Step 3:** 开库后执行规格 4.3 迁移：版本 0 且表存在则在 `createTransaction` 事务内 RENAME、CREATE、`INSERT SELECT` 12 个旧列、DROP，置版本 1；表不存在则建表置版本 2；版本 1 时逐行从 Asset Kit 读 `otp_secret_<id>`，`update` 返回 1 行才 `asset.remove`，`NOT_FOUND`（24000002）视为无密钥，全程无异常才置版本 2
- [ ] **Step 4:** 删除 `SecretVault.ets`，所有调用点改读写 `secret` 列；首页删 `secrets` 缓存，`tick(now, force)` 在 `refresh()` 时强制重算全部验证码
- [ ] **Step 5:** 编译
- [ ] **Step 6:** 模拟器升级验证：装旧版 `old.hap`，手动添加 TOTP 与 HOTP 各一个并记下验证码；覆盖安装新版，确认账号、验证码、HOTP 计数器一致，日志显示迁移条数与版本 2；再冷启动一次确认不重复迁移。若 S2 升 S3 开库报 14800017，改回 S2 并同步更新规格
- [ ] **Step 7:** 提交 `refactor(data): 密钥存入账号表，移除 Asset Kit`

### Task 2: 云同步服务与界面

**Files:**
- Create: `entry/src/main/ets/services/CloudSyncService.ets`
- Create: `entry/src/main/ets/pages/SyncPage.ets`
- Modify: `entry/src/main/ets/pages/Index.ets`、`entryability/EntryAbility.ets`
- Modify: `AppScope/app.json5`、`entry/src/main/module.json5`
- Modify: `entry/src/main/resources/base/element/string.json`、`entry/src/main/resources/en_US/element/string.json`

**Interfaces:**
- Consumes: `ACCOUNT_TABLE`、`OtpAccountStore.store(ctx)`
- Produces:

```ts
export enum CloudSyncState { OFF = 0, SYNCING = 1, SYNCED = 2, DISCONNECTED = 3 }
export interface CloudSyncStatus { state: CloudSyncState; code: number; online: boolean; lastSyncAt: number; }
export function syncStateSymbol(state: CloudSyncState): Resource;
// CloudSyncService 单例
init(ctx: common.Context): Promise<void>;
isEnabled(): boolean;
enable(ctx: common.Context): Promise<void>;
disable(ctx: common.Context): Promise<void>;
syncNow(ctx: common.Context, manual: boolean): Promise<void>;
status(): CloudSyncStatus;
onStatusChange(cb: (s: CloudSyncStatus) => void): () => void;
onCloudDataChange(cb: () => void): () => void;
guideShown(ctx: common.Context): Promise<boolean>;
markGuideShown(ctx: common.Context): Promise<void>;
release(): void;
```

- [ ] **Step 1:** `app.json5` 加 `cloudStructuredDataSyncEnabled: true`，`module.json5` 声明 `ohos.permission.GET_NETWORK_INFO`
- [ ] **Step 2:** 写 `CloudSyncService`：preferences `rotor_settings` 存开关、最近同步时间与引导标记；`enable` / `disable` / `init` 调 `setDistributedTables`（关闭用 `autoSync: false, enableCloud: false`，冷启动按开关状态重新下发一次配置）；`syncNow` 用 `SYNC_MODE_TIME_FIRST`，以进度回调的 `SYNC_FINISH` 为结束、60 秒超时兜底、自动触发 30 秒防抖；成功后通知数据变更；云端变更订阅 `SUBSCRIBE_TYPE_CLOUD`；默认网络监听 `netAvailable` / `netLost`
- [ ] **Step 3:** 写 `SyncPage`：状态卡（图标、状态文案、最近同步时间、立即同步）、开关卡（Toggle 加首次开启引导弹窗与关闭确认弹窗，失败回位并 toast）、云空间设置入口、说明文字
- [ ] **Step 4:** 首页：「更多」菜单加「云同步」，路由 `sync`；标题栏 `menu` 放状态图标，未开启时为空；`aboutToAppear` 调 `init` 并订阅状态与云端变更，`aboutToDisappear` 取消
- [ ] **Step 5:** `EntryAbility.onForeground` 调 `syncNow(ctx, false)`，`onDestroy` 调 `release()`
- [ ] **Step 6:** 规格 6.5 的全部字符串进中英文资源
- [ ] **Step 7:** 编译
- [ ] **Step 8:** 模拟器验证：「更多」菜单与云同步页布局；开启后 `setDistributedTables` 无报错、状态与右上角图标随同步结果切换（未配置 AGC 时预期为「与云断开」）、首次引导弹窗出现一次；关闭确认后图标消失；冷启动后开关状态保持；深浅色各截一张图
- [ ] **Step 9:** 提交 `feat(sync): 接入华为云空间端云同步与首页同步状态标识`

### Task 3: 文案、文档与宣传图

**Files:**
- Modify: 两份 `string.json` 的 `about_description`
- Modify: `AGENTS.md`、`README.md`
- Modify: `assets/05_privacy.svg`、`assets/05_privacy.png`

- [ ] **Step 1:** 关于页中英文案按规格 6.4
- [ ] **Step 2:** `AGENTS.md` 按规格 9.1，`README.md` 按规格 9.2
- [ ] **Step 3:** `05_privacy.svg` 按规格 9.3 改文案与图标，`rsvg-convert -w 1080 -h 1920` 重渲染 PNG 并目视检查
- [ ] **Step 4:** 编译，模拟器看一眼关于页
- [ ] **Step 5:** 提交 `docs: 关于页、README、AGENTS.md 与宣传图按云同步现状更新`

### Task 4: 交付

- [ ] **Step 1:** 推送 `feat/cloud-sync` 分支
- [ ] **Step 2:** 向用户说明：AGC 云侧配置步骤（规格 5.2）、双机真机验证场景（规格 11）、合并前注意共用真机上的旧版本会读不到已迁移的密钥
