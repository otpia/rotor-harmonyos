# Rotor · HarmonyOS 上架素材

> 本仓库为 Rotor —— 一款本地优先的 HarmonyOS NEXT 双因素动态验证码 App。本文档汇总应用商店上架所需的文案与宣传图素材。

---

## 一句话简介（17 字以内）

**本地优先的双因素动态验证码**

备选：

- 为鸿蒙打造的本地双因素验证器
- 安全轻巧的本地双因素验证器

---

## 应用介绍

Rotor 是一款专为 HarmonyOS NEXT 打造的本地双因素动态验证码工具，遵循 RFC 6238 标准，与 Google Authenticator 等主流验证器完全兼容。

· 本地优先：账号与密钥默认只保存在本机。
· 云同步：开启后经华为云空间在登录同一华为账号的设备间自动同步，密钥、名称、描述以加密字段存储。
· 扫码秒加：扫描 otpauth:// 二维码一键导入，也可手动输入；新增、编辑、删除、搜索一目了然。
· 30 秒一变：粗体大字号验证码配合圆环倒计时，过期前 6 秒自动高亮，不错过任何窗口。
· 加密备份：AES-256 + PBKDF2-SHA256（200K 迭代）打包导出 .rotorbak 文件，自定义密码跨设备迁移；导入按 secret 自动去重。
· 跟随主题：原生适配深浅双色，全天候护眼。
· 真正轻量：除相机权限外不申请任何敏感权限，无广告、无埋点、无追踪；应用自身不联网，云同步由系统云空间服务完成。

Rotor 不堆砌花哨功能，只把你的双因素验证码安全、清爽地放在指尖。

---

## 权限说明

Rotor 严格遵循"最小权限原则"，全应用申请 **2 项** 系统权限（其中 1 项由系统自动授予、不弹窗），另声明 **1 项** 不向用户申请授权的系统备份扩展能力。

**申请的系统权限**

| 权限名 | 权限类型 | 申请时机 | 用途 |
| --- | --- | --- | --- |
| `ohos.permission.CAMERA`（相机） | 敏感权限 · 仅使用时（`when: inuse`） | 用户首次进入"扫描二维码"页面时按需弹窗授权 | 调用系统 Scan Kit 扫描 `otpauth://` 标准二维码以快速添加账号；不录像、不录音、不读取相册、不上传图像数据 |
| `ohos.permission.GET_NETWORK_INFO`（获取网络信息） | 普通权限 · 系统授予（`system_grant`） | 安装时由系统自动授予，不弹窗 | 开启云同步后监听默认网络的连接状态，在首页与云同步页显示与云的连接状态；应用不直接访问网络 |

**系统备份扩展能力（ExtensionAbility · 不向用户申请权限）**

| 能力名 | 类型 | 导出 | 用途 |
| --- | --- | --- | --- |
| `EntryBackupAbility` | `BackupExtensionAbility`（`@kit.CoreFileKit`） | `exported: false`，仅系统可调用 | 参与 HarmonyOS 系统级"换机克隆 / 整机备份恢复"流程；由 `backup_config.json` 控制（当前 `allowToBackupRestore: true`）。账号与密钥（应用沙箱内 SQLite）随系统通道迁移 |

**未申请的能力（明确不需要）**

- ❌ 网络访问（`INTERNET`）：应用自身不联网；开启云同步后由系统云空间服务在登录同一华为账号的设备间同步，不连接任何第三方服务器
- ❌ 存储（`READ_MEDIA` / `WRITE_MEDIA`）：备份导入导出走系统文件选择器（CoreFileKit Picker），无需常驻存储权限
- ❌ 位置、麦克风、通讯录、日历、通知等所有其他敏感权限均不申请

**数据存储边界**

- 账号与密钥（名称、备注、算法参数、base32 密钥）→ 应用内 **关系型数据库（ArkData / SQLite，安全等级 S3）**，位于应用沙箱，其他应用不可读
- 开启云同步后 → 用户本人的 **华为云空间**（端云同步容器 `rotor`），`secret`、`name`、`note` 为云侧加密字段；用户可在系统「设置 - 云空间」中管理或删除
- 加密备份文件（`.rotorbak`）→ 由用户在系统文件选择器中选定的位置，由用户自行管理

---

## 宣传图

| #   | 主题       | 文案                       | 截图                                          |
| --- | ---------- | -------------------------- | --------------------------------------------- |
| 1   | 品牌欢迎   | 本地优先的双因素动态验证码 | [01_hero.png](assets/01_hero.png)             |
| 2   | 列表与倒计时 | 30 秒一变 · 一目了然        | [02_list.png](assets/02_list.png)             |
| 3   | 扫码秒加   | 扫码秒加 · 一键导入         | [03_scan.png](assets/03_scan.png)             |
| 4   | 加密备份   | AES 加密备份 · 安心迁移     | [04_backup.png](assets/04_backup.png)         |
| 5   | 多设备同步 | 多设备 · 同一套验证码       | [05_privacy.png](assets/05_privacy.png)       |

### 预览

![品牌欢迎](assets/01_hero.png)
![列表与倒计时](assets/02_list.png)
![扫码秒加](assets/03_scan.png)
![加密备份](assets/04_backup.png)
![多设备同步](assets/05_privacy.png)

---

## 素材规格

- **尺寸**：1080 × 1920 px（9:16，按上架要求 3x 物理像素直接交付）
- **格式**：PNG（8-bit RGB / RGBA，非交错）
- **大小**：5 张图均 < 300 KB，符合 PNG/JPG/JPEG ≤ 5 MB 限制
- **字体**：PingFang SC / Hiragino Sans GB / Heiti SC（系统兜底）
- **配色**：与应用同色板（accent #0A59F7、bg #F1F3F5、text #0F1B2D）

## 文件清单

```
assets/
├── 01_hero.svg     01_hero.png      品牌欢迎页
├── 02_list.svg     02_list.png      首页 OTP 列表 + 圆环倒计时
├── 03_scan.svg     03_scan.png      扫码导入界面
├── 04_backup.svg   04_backup.png    AES 加密备份
└── 05_privacy.svg  05_privacy.png   多设备同步（深色品牌）
```

## 重新生成

每张 PNG 由对应同名 SVG 通过 `rsvg-convert` 渲染。修改文案或样式后，在 `assets/` 目录下执行：

```bash
for f in assets/*.svg; do
  rsvg-convert -w 1080 -h 1920 "$f" -o "${f%.svg}.png"
done
```

如需 JPEG / WEBP 版本（WEBP 单文件需 < 200 KB）：

```bash
# JPEG（高质量）
magick assets/01_hero.png -quality 92 assets/01_hero.jpg
# WEBP（压缩到 200 KB 以内）
magick assets/01_hero.png -define webp:target-size=200000 assets/01_hero.webp
```
