# Rotor 云同步设计

日期：2026-09-24
状态：设计已逐节确认，待实施
范围：账号与密钥经华为云空间在同一华为账号的设备间同步；密钥存储从 Asset Kit 迁入数据库；新增「云同步」二级页；相关文档与上架素材同步更新

## 1. 背景与目标

Rotor 当前是纯本地的 TOTP / HOTP 验证器：账号资料存 `rotor.db`（relationalStore，S2），密钥单独存 Asset Kit，跨设备只能靠手动导出 `.rotorbak` 加密备份再导入。目标是让用户在登录同一华为账号的多台设备上自动拥有同一套账号与密钥，新设备零额外操作，删除与修改也跟着同步。

## 2. 方案选择

采用 ArkData 关系型数据库的端云同步（华为云空间）。数据存在用户自己的云空间配额里，开发者不需要服务器、不产生费用、不涉及 ICP 备案；同步由系统调度，支持自动同步与手动同步，云端变更有订阅通知。

被否决的方案与原因：

| 方案 | 否决原因 |
| --- | --- |
| 端云文件协同（把加密备份文件写进沙箱 cloud 目录） | 只是自动备份，删除不同步、字段级冲突无法合并 |
| Cloud Foundation Kit 云数据库 | 需要用户凭据、需要 ICP 备案、按量计费、数据放在开发者项目里 |
| 自建服务器或 WebDAV | 运维与备案成本，信任模型最差 |
| 同步口令端到端加密 | 用户不需要额外口令这一层，接受安全边界等于华为账号 |

## 3. 已确认的决策

| 编号 | 决策 | 结论 |
| --- | --- | --- |
| D1 | 底层通道 | ArkData 端云同步（华为云空间） |
| D2 | 密钥保护 | 不设同步口令；密钥明文写入本地表，云侧字段选 Encrypted String |
| D3 | Asset Kit | 移除，表为唯一真源；存量密钥升级时迁入表 |
| D4 | 数据库文件加密 | 不加密（`encrypt` 保持默认 false） |
| D5 | 启用语义 | 应用内显式开启后表才成为端云同步表；关闭只停止同步，云端数据保留 |
| D6 | HOTP 计数器 | 随行同步，以修改时间新的一端为准 |
| D7 | 云侧加密字段 | `secret`、`name`、`note` 三列选 Encrypted String |
| D8 | 设置入口 | 「更多」菜单加「云同步」项，进入新的二级页 |
| D9 | 重复账号 | 不自动处理，两条都显示，用户手动删 |
| D10 | 网络策略 | 不调 `setCloudStrategy`，用系统默认（WLAN 与蜂窝） |
| D11 | 网络监听 | 接 Network Kit 默认网络监听，声明 `ohos.permission.GET_NETWORK_INFO` |
| D12 | 关于页文案 | 陈述本机存储与开启云同步后两种状态 |
| D13 | 宣传图第 5 张 | 本次一并改，文案按「多设备同步作为卖点」方向 |

## 4. 数据层

### 4.1 表结构

账号表为 `OtpAccount`，结构如下。所有列不带 `NOT NULL`（端云同步表不允许），`DEFAULT` 保留；主键 `id` 为 UUID 文本，满足「设备间主键唯一、不能自增」的要求。新增 `secret` 列存 base32 明文密钥，不设默认值，`NULL` 或空串都视为「尚无密钥」。

```sql
CREATE TABLE IF NOT EXISTS OtpAccount (
  id TEXT PRIMARY KEY,
  name TEXT DEFAULT '',
  note TEXT DEFAULT '',
  type TEXT DEFAULT 'totp',
  period INTEGER DEFAULT 30,
  digits INTEGER DEFAULT 6,
  algorithm TEXT DEFAULT 'SHA1',
  counter INTEGER DEFAULT 0,
  iconKey TEXT DEFAULT '',
  orderIndex INTEGER DEFAULT 0,
  createdAt INTEGER DEFAULT 0,
  updatedAt INTEGER DEFAULT 0,
  secret TEXT
)
```

库名沿用 `rotor.db`，表名为 `OtpAccount`：AGC 容器名必须与库名（去后缀）一致，数据类型名必须与表名一致，且只允许字母和数字、以字母开头。表列以后只能新增不能修改删除，本版字段即为定稿。

`name`、`note`、`secret` 在 AGC 上是 Encrypted String，这三列的空值一律存 `NULL`、不存空串：云空间对空串加密会失败，整条记录随之上传失败。写入时空串转 `NULL`，读取时 `NULL` 按空串处理。

`OtpAccount` 模型新增 `secret: string`，`defaultAccount()` 与 `cloneAccount()` 同步补上；读取行时每一列都按默认值兜底（`isColumnNull` 判断），云端来的行某列为空时不报错。

### 4.2 数据库配置

```ts
const CONFIG: relationalStore.StoreConfig = {
  name: 'rotor.db',
  securityLevel: relationalStore.SecurityLevel.S3
};
```

- `securityLevel` 从 S2 提到 S3。官方规定安全等级只能升不能降；S3 允许端云同步，S4 不允许。现网 S2 库直接以 S3 配置开库即完成升级，不报 14800017。
- `encrypt` 不设置，保持非加密库（D4）。
- `autoCleanDirtyData` 不设置，保持默认 true：云端删除的行同步到本机时自动删除。

### 4.3 版本迁移

用 `RdbStore.version` 记录结构版本，在 `initStore` 中开库后立即执行，先于任何读写，也先于 `setDistributedTables`（重建必须发生在表成为端云同步表之前）。

| 版本 | 含义 |
| --- | --- |
| 0 | 现网库：旧表 `otp_account`（列带 `NOT NULL`，密钥在 Asset Kit）；或全新安装尚未建表 |
| 3 | `OtpAccount` 已按 4.1 建好，存量密钥全部在 `secret` 列，加密列没有空串 |

步骤（按表的实际状态判断，中途被杀下次启动接着做）：

1. `OtpAccount` 已存在且 `version` 为 3：已完成，直接返回。
2. `OtpAccount` 不存在：
   - 旧表 `otp_account` 存在：在一个事务内按 4.1 建 `OtpAccount`、`INSERT INTO OtpAccount (12 个旧列) SELECT 12 个旧列 FROM otp_account`（旧表已有 `secret` 列时连同 `secret` 一起搬）、`DROP TABLE otp_account`。事务失败整体回滚，下次启动重试。
   - 旧表也不存在：按 4.1 建表。
3. 查 `SELECT id FROM OtpAccount WHERE secret IS NULL OR secret = ''`，逐行用别名 `otp_secret_<id>` 从 Asset Kit 读密钥：读到则 `UPDATE` 该行 `secret`，返回 1 行才 `asset.remove` 该条；读不到（Asset 里没有）视为该账号无密钥，跳过。
4. 对 `name`、`note`、`secret` 各执行一次 `UPDATE OtpAccount SET <列> = NULL WHERE <列> = ''`。第 3、4 步全程没有异常才置 `version = 3`，否则下次启动接着跑。
5. 仍没有密钥的账号在首页显示 `------`，用户可在编辑页补录密钥或删除。

### 4.4 Asset Kit 移除

- 删除 `services/SecretVault.ets`。4.3 第 3 步的 Asset 读取与删除逻辑写在 `OtpAccountStore` 的迁移函数里，是代码中最后一处 Asset Kit 引用，下个大版本可整体删除。
- 编辑页保存、扫码批量导入、备份导入直接写 `acct.secret` 后调一次 `insert` 或 `update`；管理页导出直接读 `a.secret`；首页删除只调 `OtpAccountStore.delete`。
- 首页的 `secrets` 缓存字典删除，卡片出码直接用 `a.secret`。
- `AccountDedup.existingSecretSet` 改为从 `listAll` 结果取 `secret` 列。

## 5. 云同步接入

### 5.1 应用声明

`AppScope/app.json5`：

```json
{
  "app": {
    "cloudStructuredDataSyncEnabled": true
  }
}
```

声明后系统「设置 - 云空间」的应用列表出现 Rotor 的同步开关。只要应用没有把表设为端云同步表，该开关打开也不会上传任何数据。

`entry/src/main/module.json5` 的 `requestPermissions` 增加 `ohos.permission.GET_NETWORK_INFO`（系统自动授予的普通权限，只需 `name`，供 5.6 网络监听使用）。

`setDistributedTables` 的接口注解标有 `ohos.permission.DISTRIBUTED_DATASYNC`，编译时会出权限提示；端云类型（`DISTRIBUTED_CLOUD`）在 API 12 起运行时不需要该权限，不声明。

### 5.2 AGC 云侧配置

一次性手工操作，开发环境与生产环境各做一次（先开发环境调通，再「实施变更到生产环境」，实施后字段只能加不能改删）：

1. AppGallery Connect -> 项目 -> Rotor 应用 -> 开通「云空间服务」（在「全部功能 > 构建 > 云空间服务」，可固定到左侧导航）。
2. 创建容器，名称 `rotor`。
3. 新建数据类型 `OtpAccount`，字段如下（字段名区分大小写）；高级设置里「端侧去重主键」勾选 `id`。

| 字段 | 云侧类型 |
| --- | --- |
| id | String |
| name | Encrypted String |
| note | Encrypted String |
| type | String |
| period | Integer |
| digits | Integer |
| algorithm | String |
| counter | Integer |
| iconKey | String |
| orderIndex | Integer |
| createdAt | Integer |
| updatedAt | Integer |
| secret | Encrypted String |

环境连接由证书类型决定：`product=device`（调试证书）连开发环境，`product=default`（发布证书）连生产环境。云侧配置有改动后，端侧要退出华为账号再登录才能拿到新配置。

### 5.3 `services/CloudSyncService.ets`

单例，封装全部端云逻辑。开关与最近同步时间持久化在 `preferences`（文件 `rotor_settings`，键 `cloudSyncEnabled: boolean`、`lastSyncAt: number`），不放进数据库以免自身被同步。

```ts
export enum CloudSyncState { OFF, SYNCING, SYNCED, DISCONNECTED }

export interface CloudSyncStatus {
  state: CloudSyncState;
  code: number;        // 最近一次同步结束时的 ProgressCode；本进程尚未完成首次同步为 CODE_PENDING（-2），调用抛异常或超时为 CODE_FAILED（-1）
  online: boolean;     // 默认网络是否可用
  lastSyncAt: number;  // 最近一次成功同步的时间戳，0 表示从未成功
}

export function syncStateSymbol(state: CloudSyncState): Resource;   // 状态对应的 sys.symbol 图标

class CloudSyncService {
  init(ctx): Promise<void>;                      // 冷启动调用
  isEnabled(): boolean;
  enable(ctx): Promise<void>;
  disable(ctx): Promise<void>;
  syncNow(ctx, manual: boolean): Promise<void>;  // manual 为 true 忽略防抖
  status(): CloudSyncStatus;
  onStatusChange(cb: (s: CloudSyncStatus) => void): () => void;   // 返回取消函数
  onCloudDataChange(cb: () => void): () => void;                  // 返回取消函数
  guideShown(ctx): Promise<boolean>;             // 首次开启引导弹窗是否已出现过
  markGuideShown(ctx): Promise<void>;
  release(): void;                               // 进程退出时调用：取消订阅、注销网络监听
}
```

- `init`：读 preferences；开关为开时，调 `setDistributedTables(['OtpAccount'], DISTRIBUTED_CLOUD, { autoSync: true })`（幂等，保证配置存在）、注册云端变更订阅、启动网络监听、调一次 `syncNow(ctx, false)`。开关为关且 preferences 里明确记过关闭时，重新下发一次 `{ autoSync: false, enableCloud: false }`，保证关闭状态在系统侧生效；从未开启过则不做其他事。
- `enable`：调 `setDistributedTables(['OtpAccount'], DISTRIBUTED_CLOUD, { autoSync: true, enableCloud: true })`，成功后记开关为开，注册云端变更订阅，启动网络监听，调 `syncNow(ctx, true)`。`setDistributedTables` 失败则保持关闭状态并向调用方抛出，页面据此提示「开启失败」。首次 `setDistributedTables` 后系统自动把本地已有行全部上传；手动同步用时间优先模式合并云端已有数据（另一台设备先开启的情况）。
- `disable`：调 `setDistributedTables(['OtpAccount'], DISTRIBUTED_CLOUD, { autoSync: false, enableCloud: false })`，记开关为关，取消云端变更订阅，停止网络监听，状态置 `OFF`。调用失败则保持开启状态并向调用方抛出，页面据此提示「关闭失败」。本地数据不动，云端数据保留；删除云端数据由用户在系统云空间的「停止同步并删除云端数据」完成。
- `syncNow`：`store.cloudSync(SyncMode.SYNC_MODE_TIME_FIRST, ['OtpAccount'], progress)`（Promise 版）。`manual` 为 false 时，上次同步成功且距上次实际执行不足 30 秒直接返回，避免被云端限流；上次同步失败或尚未同步过则立即执行，保证从系统云空间打开开关返回后能马上刷新状态。防抖计时只保存在内存里；`manual` 为 true 不受防抖限制，但同步进行中再次调用直接返回。进度回调里 `schedule` 为 `SYNC_FINISH` 时取 `code`，`SUCCESS` 则更新 `lastSyncAt` 并写入 preferences。
- 所有 relationalStore 与 preferences 调用都包 try/catch，异常记 `console.error` 并把状态置为 `DISCONNECTED`、`code = -1`。
- `RdbStore` 实例通过 `OtpAccountStore.store(ctx)` 取得（把现有模块私有的 `getStore` 暴露为静态方法），不另开库。

### 5.4 状态判定

| 状态 | 条件 |
| --- | --- |
| `OFF` | 开关为关 |
| `SYNCING` | 有一次 `cloudSync` 调用在进行中，或本进程尚未完成首次同步且网络可用（冷启动与刚开启时总会立即同步一次） |
| `SYNCED` | 网络可用，且最近一次 `cloudSync` 结束码为 `SUCCESS` |
| `DISCONNECTED` | 开关为开且不满足上面两条：网络不可用，或最近一次结束码不是 `SUCCESS`，或调用抛异常 |

「与云断开」按用户定义覆盖所有未成功的情形：没网络、未登录华为账号、系统开关未开、云空间存储满、超出数据上限、被其他设备占用。具体原因在云同步页按 5.7 的文案显示。

系统自动同步（`autoSync`）不向应用回报进度，所以 `SYNCING` 只在应用自己发起的手动同步期间出现。

### 5.5 同步时机与刷新

- 冷启动：首页 `aboutToAppear` 调 `CloudSyncService.init(ctx)`，`init` 内部先 `await OtpAccountStore.store(ctx)` 等迁移完成再设置分布式表，最后同步一次（受防抖，进程内首次总会执行）。
- 回前台：`EntryAbility.onForeground` 调 `syncNow(ctx, false)`（受防抖）。
- 网络恢复：`netAvailable` 回调里调 `syncNow(ctx, false)`（受防抖）。
- 用户点「立即同步」：`syncNow(ctx, true)`。
- 本地增删改之后不主动触发同步，交给 `autoSync` 由系统调度上传；HOTP 点刷新写库也一样。
- 云端变更：`store.on('dataChange', SubscribeType.SUBSCRIBE_TYPE_CLOUD, observer)`，回调里通知 `onCloudDataChange` 的订阅者。首页注册订阅者，收到通知就走现有的 `refresh()`（重新 `listAll`，云端删除的行已被自动清理）；页面 `aboutToDisappear` 时取消。

### 5.6 网络监听

`connection.createNetConnection()` 关注默认网络，`on('netAvailable')` 置网络可用并触发同步，`on('netLost')` 置网络不可用，然后 `register()`；`disable` 时与 `release()`（由 `EntryAbility.onDestroy` 调用）里 `unregister()`。初始值用 `connection.hasDefaultNetSync()`。

### 5.7 状态文案

`code` 到文案的映射，中英文各一份进 `string.json`：

| `ProgressCode` | 值 | 中文文案 |
| --- | --- | --- |
| `SUCCESS` | 0 | 已与云空间同步 |
| `UNKNOWN_ERROR` | 1 | 同步已暂停 |
| `NETWORK_ERROR` | 2 | 网络错误，同步已暂停 |
| `CLOUD_DISABLED` | 3 | 未开启同步 |
| `LOCKED_BY_OTHERS` | 4 | 同步已暂停，稍后自动重试 |
| `RECORD_LIMIT_EXCEEDED` | 5 | 超出数据上限，同步已暂停 |
| `NO_SPACE_FOR_ASSET` | 6 | 云空间存储空间不足 |
| `BLOCKED_BY_NETWORK_STRATEGY` | 7 | 未连接 WLAN，同步已暂停 |
| `STOP_CLOUD_SYNC` | 8 | 同步已停止 |
| 调用抛异常 | -1 | 同步失败 |

`SYNCING` 显示「正在与云空间同步」；网络不可用且无结束码时显示「网络错误，同步已暂停」；`OFF` 显示「未开启」。

## 6. 界面

### 6.1 「更多」菜单

新增一项「云同步」，图标 `sys.symbol.icloud`，顺序：导入备份、编辑、云同步、关于。路由名 `sync`，加入 `PageMap`。

### 6.2 `pages/SyncPage.ets`

`HdsNavDestination`，标题「云同步」，标题栏样式与编辑页一致（`GRADIENT_BLUR` 加 `systemMaterialEffect` ADAPTIVE，`enableComponentSafeArea`）。内容为 `Scroll` 内三张卡，卡片样式沿用编辑页（`comp_background_list_card`、`corner_radius_level8`、行高 56）：

1. 状态卡：左侧状态图标取系统符号库，已同步 `sys.symbol.checkmark_icloud_fill`，同步中 `sys.symbol.icloud_badge_arrow_2_circlepath`，与云断开 `sys.symbol.icloud_slash`，未开启 `sys.symbol.icloud`；右侧第一行状态文案（5.7），第二行「最近同步 <时间>」，`lastSyncAt` 为 0 时不显示第二行，时间按系统区域格式化为月日时分。卡片底部「立即同步」按钮，`OFF` 时不显示，`SYNCING` 时禁用。
2. 开关卡：一行「云同步」加系统 `Toggle({ type: ToggleType.Switch })`。打开时调 `enable`，失败则 Toggle 回到关闭并 toast「开启失败」；本安装首次打开成功后弹 `AlertDialog`（`ULTRA_THICK` 材质）：文案「还需在系统云空间中打开 Rotor 的同步开关」，按钮「去开启」执行 `openLink('hicloud://cloudDrive/getInfo?path=MainActivity')`、「稍后」关闭；是否首次用 preferences 键 `syncGuideShown` 记录。关闭时先弹确认：文案「关闭后本机数据保留，云端已同步的数据仍保存在云空间，可在系统云空间中删除」，按钮「取消」与「关闭」（警示色），确认才调 `disable`，失败则 Toggle 保持打开并 toast「关闭失败」；取消则 Toggle 回到打开。
3. 入口卡：一行「云空间设置」带右侧 `sys.symbol.chevron_right`，点击 `openLink` 同上。

卡片下方说明文字（`Body_M`、`font_secondary`）：「开启后，账号与密钥存入你的华为云空间，在登录同一华为账号的设备间同步。同步开关需在系统「设置 - 云空间」中打开。」

### 6.3 关于页文案

`about_description` 改为：

- 中文：「Rotor 是一款本地优先的双因素验证码 App，遵循 RFC 6238。密钥保存在本机应用数据库中；开启云同步后，密钥存入你的华为云空间，在登录同一华为账号的设备间同步。」
- 英文：「Rotor is a local-first 2FA app following RFC 6238. Secrets are stored in the app's local database on this device. With cloud sync on, they are stored in your Huawei Cloud and synced across devices signed in with the same HUAWEI ID.」

### 6.4 新增字符串资源

| 键 | 中文 | 英文 |
| --- | --- | --- |
| `menu_sync` | 云同步 | Cloud sync |
| `sync_title` | 云同步 | Cloud sync |
| `sync_switch` | 云同步 | Cloud sync |
| `sync_now` | 立即同步 | Sync now |
| `sync_cloud_settings` | 云空间设置 | Cloud settings |
| `sync_last_time` | 最近同步 %s | Last synced %s |
| `sync_description` | 开启后，账号与密钥存入你的华为云空间，在登录同一华为账号的设备间同步。同步开关需在系统「设置 - 云空间」中打开。 | When enabled, accounts and secrets are stored in your Huawei Cloud and synced across devices signed in with the same HUAWEI ID. The sync switch must be turned on in Settings > Cloud. |
| `sync_enable_dialog` | 还需在系统云空间中打开 Rotor 的同步开关 | Turn on the Rotor sync switch in Cloud settings to start syncing |
| `btn_go_enable` | 去开启 | Open settings |
| `btn_later` | 稍后 | Later |
| `sync_disable_confirm` | 关闭后本机数据保留，云端已同步的数据仍保存在云空间，可在系统云空间中删除 | Local data stays on this device. Data already synced stays in Cloud and can be deleted in Cloud settings. |
| `btn_turn_off` | 关闭 | Turn off |
| `toast_sync_enable_failed` | 开启失败 | Failed to turn on sync |
| `toast_sync_disable_failed` | 关闭失败 | Failed to turn off sync |
| `sync_state_off` | 未开启 | Off |
| `sync_state_syncing` | 正在与云空间同步 | Syncing with Cloud |
| `sync_state_synced` | 已与云空间同步 | Synced with Cloud |
| `sync_state_paused` | 同步已暂停 | Sync paused |
| `sync_state_network` | 网络错误，同步已暂停 | Network error, sync paused |
| `sync_state_cloud_disabled` | 未开启同步 | Sync not enabled |
| `sync_state_locked` | 同步已暂停，稍后自动重试 | Sync paused, will retry later |
| `sync_state_limit` | 超出数据上限，同步已暂停 | Data limit exceeded, sync paused |
| `sync_state_no_space` | 云空间存储空间不足 | Cloud storage is full |
| `sync_state_strategy` | 未连接 WLAN，同步已暂停 | Not on WLAN, sync paused |
| `sync_state_stopped` | 同步已停止 | Sync stopped |
| `sync_state_failed` | 同步失败 | Sync failed |

## 7. 改动清单

| 文件 | 改动 |
| --- | --- |
| `model/OtpAccount.ets` | 加 `secret` 字段 |
| `services/OtpAccountStore.ets` | 4.1 表结构、4.3 迁移、`secret` 列读写、加密列空值存 `NULL`、空值兜底、暴露 `store(ctx)` |
| `services/SecretVault.ets` | 删除 |
| `services/AccountDedup.ets` | 从表取 `secret` |
| `services/CloudSyncService.ets` | 新增，第 5 节全部 |
| `services/ScanService.ets` | 写 `acct.secret`，去掉 Asset 调用 |
| `services/BackupImporter.ets` | 同上 |
| `pages/Index.ets` | 删 `secrets` 缓存；卡片用 `a.secret`；「更多」菜单加「云同步」；`aboutToAppear` 调 `CloudSyncService.init` 并订阅云端变更；路由 `sync` |
| `pages/EditPage.ets` | 保存写 `account.secret` |
| `pages/ManagePage.ets` | 导出读 `a.secret`；删除去掉 Asset 调用 |
| `pages/SyncPage.ets` | 新增 |
| `pages/AboutPage.ets` | 无代码改动 |
| `entryability/EntryAbility.ets` | `onForeground` 调 `syncNow`，`onDestroy` 调 `release` |
| `AppScope/app.json5` | `cloudStructuredDataSyncEnabled: true` |
| `entry/src/main/module.json5` | 声明 `ohos.permission.GET_NETWORK_INFO` |
| `resources/base/element/string.json`、`resources/en_US/element/string.json` | 6.3、6.4 文案 |
| `AGENTS.md` | 见 9.1 |
| `README.md` | 见 9.2 |
| `assets/05_privacy.svg` 及渲染产物 | 见 9.3 |

## 8. 边界与异常

- 未登录华为账号、海外账号、系统开关未开：`setDistributedTables` 成功，手动同步结束码为 `CLOUD_DISABLED`，云同步页显示「未开启同步」与「云空间设置」入口。
- 云端删除：本地行自动清理，首页刷新即消失。
- 两台设备各自添加同一账号：两条都保留，用户手动删。
- HOTP 计数器随行同步；两台设备短时间内先后刷新，较早的加一会被较晚的值覆盖。
- 限流：自动触发的同步 30 秒防抖，本地写入后不主动同步。
- 迁移：重建在事务内，失败回滚保持版本 0，下次启动重试；Asset 搬迁逐行幂等。
- 表结构定稿后只能加列；AGC 生产环境实施后字段不能改删。
- 云侧配置改动后需退出华为账号再登录。
- 数据量：单条不足 1 KB，几十到几百条，远低于云端限制。
- 平台约束：仅中国大陆；要求 HarmonyOS 6.1.0 与云空间 6.3.0 起，工程 `compatibleSdkVersion` 为 26.0.0 已高于系统要求，云空间应用版本在验证机上确认。
- 所有 relationalStore、preferences、Network Kit、`openLink` 调用包 try/catch，失败记日志不崩溃。

## 9. 文档与素材同步

### 9.1 `AGENTS.md`

- 「关键文件」加 `pages/SyncPage.ets`（云同步开关、状态、立即同步、跳转云空间）与 `services/CloudSyncService.ets`（端云同步、网络监听、状态）。
- 「ArkTS 注意」删去 Asset Kit 一条。
- 「调试流程」加一条：云同步调试用 `product=device` 连 AGC 开发环境，需两台登录同一华为账号的真机。

### 9.2 `README.md`

按现状改写以下描述：密钥仅写入系统级凭据库、永不上云、全程离线、不申请网络权限、密钥不通过系统备份通道迁移、密钥位于 Asset Store Kit。改后的事实：账号资料与密钥同在应用沙箱内 `rotor.db`（S3），随系统换机克隆通道迁移；开启云同步后经华为云空间在同账号设备间同步，`secret`、`name`、`note` 为云侧加密字段；应用不直接联网，同步由系统云空间服务完成；声明 `GET_NETWORK_INFO` 仅用于显示云同步连接状态。宣传图表格第 5 行主题改「多设备同步」，文案改「多设备 · 同一套验证码」。

### 9.3 宣传图第 5 张

`assets/05_privacy.svg` 五组文字改为下表，同时把原图的「秘钥」改正为「密钥」；改完在仓库根执行 README 中的 `rsvg-convert` 命令重渲染 `05_privacy.png`。

| 位置 | 新文案 |
| --- | --- |
| 大标题 | 多设备 · 同一套验证码 |
| 盾牌内图形 | 白色云朵加蓝色对勾 |
| 副标题 | 华为云空间同步 · 同账号设备自动一致 |
| 中部标题 | 本地优先 · 同步可选 |
| 中部说明 | 不开同步，数据不出本机 |
| 卡 1 标题 | 云空间加密存储 |
| 卡 1 说明 | 密钥、名称、描述以加密字段存入你的华为云空间 |
| 卡 2 标题 | 无广告 · 无埋点 · 无追踪 |
| 卡 2 说明 | 同步由系统云空间完成 · 不连接任何第三方服务器 |
| 卡 3 标题 | RFC 6238 标准兼容 |
| 卡 3 说明 | 与 Google Authenticator 等主流验证器互通 |

## 10. 上线前事项

- AGC 隐私政策补一句：「为了在你的设备间同步验证码账号，通过华为云空间在已登录华为账号的设备间同步账号名称、描述、密钥等数据。你可以在“设置-云空间”里管理同步功能和存储在云空间的数据。」
- 开发环境调通后在 AGC「实施变更到生产环境」，再用 `product=default` 发布包验证生产环境同步。

## 11. 验证方式

- 不写单元测试。hvigor 编译、hdc 装真机、截图核对。
- 升级验证：先装当前 master 构建并添加几个账号（含一个 HOTP），覆盖安装新版，确认账号与密钥完整、验证码正确、Asset Kit 已清空、`version` 为 3、库里只剩 `OtpAccount` 表、加密列没有空串。
- 同步验证需要两台登录同一华为账号的真机。只有一台时用 AGC「数据记录调测」页看云端行是否出现，加密字段看不到内容，只能看 `id`、`type` 等明文列。
- 场景：A 开启后云端出现全部行；B 开启后拉到全部账号并能出码；A 改名、B 更新；A 删除、B 消失；A 断网后云同步页显示「网络错误，同步已暂停」、恢复后自动同步回到「已与云空间同步」；A 关闭后再改名，B 不变；HOTP 在 A 刷新，B 的计数器跟上。

## 12. 实施顺序

每步跑通并真机验证后单独提交：

1. 数据层：模型加 `secret`、表重建与迁移、Asset Kit 移除、各页面改用 `secret` 列。验证升级路径。
2. 云同步服务：`app.json5` 声明、AGC 开发环境配置、`CloudSyncService`（开启、关闭、手动同步、云端变更刷新）、云同步页最简版（开关、状态文字、立即同步）。验证双机同步。
3. 界面完整版：云同步页三张卡与对话框、网络监听与权限、全部文案资源。
4. 文案与素材：关于页、`AGENTS.md`、`README.md`、宣传图第 5 张。
5. AGC 实施变更到生产环境，发布包验证。

## 参考

- 端云数据同步云侧环境部署指导：https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/data-sync-with-cloud
- 端云数据同步关系型数据库端侧开发指导：https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/data-cloud-sync-of-rdb-store
- 同应用端云数据同步概述：https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/data-cloud-sync-overview
- 同步（备份恢复）关键资产：https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/asset-js-sync
- HdsNavigation：https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ui-design-hdsnavigation
- @ohos.net.connection：https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-net-connection
