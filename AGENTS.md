# rotor-harmonyos 项目规则

## 平台
- HarmonyOS NEXT，ArkTS + ArkUI 声明式；SDK 版本以 `build-profile.json5` 为准
- Bundle：`com.liasica.rotor`

## 设计规范
- 视觉与交互按 HarmonyOS 官方 UI Design Kit（HDS 组件）与沉浸光感规范实现，不参考外部设计稿
- 颜色、字号、圆角、间距一律用系统资源 `$r('sys.color.*')`、`$r('sys.float.*')`，不自定义颜色 token，深浅色由系统资源自动适配
- 界面图标用 `SymbolGlyph($r('sys.symbol.*'))`；issuer 品牌图标为 `media` 下的 PNG，未命中时用 `IssuerAvatar` 首字母头像
- 页面结构：`Index` 为 `HdsNavigation` 根，二级页为 `HdsNavDestination`，通过 `NavPathStack` 路由；首页标题栏为大标题加常驻搜索框（`bottomBuilder`，随上滑收起），操作全部收在 `HdsTabs` 悬浮栏（智感握姿跟手），其中「搜索」为回顶并聚焦搜索框
- 二级页返回首页的刷新统一走 `NavPathStack.setInterception.didShow`，不要依赖 `pushPathByName` 的 `onPop`（`pop(true)` 会匹配 `pop(animated)` 重载，不触发回调）
- 弹窗一律用系统能力：`AlertDialog`、`bindMenu`、`bindSheet`、`Select`、`showToast`，不自绘弹窗

## 调试流程
- 命令行编译前先设置环境。hvigor 取 PATH 里的 `java`，必须指向 DevEco 自带的 JBR：
  ```bash
  export DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk
  export JAVA_HOME=/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home
  export PATH="$JAVA_HOME/bin:/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains:$PATH"
  ```
- 编译命令：`/Applications/DevEco-Studio.app/Contents/tools/node/bin/node /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw.js --mode module -p module=entry@default -p product=device -p requiredDeviceType=phone assembleHap --analyze=normal --parallel --incremental --daemon`。`product=device` 用调试证书（profile 内含真机 UDID，模拟器也可装），产物在 `entry/build/device/outputs/default/`；发布包用 `product=default`（AppGallery 发布证书，不能 hdc 侧载）
- 签名阶段报 `Invalid CEN header` 时，先 `hvigorw.js --stop-daemon` 并 `pkill -f hvigor-java-daemon`，再重新编译（守护进程持有已被替换的工具 jar）
- 开发完一个功能（commit 后）必须用 hdc 真机验证：
  ```bash
  hdc install -r entry/build/device/outputs/default/entry-default-signed.hap
  hdc shell aa force-stop com.liasica.rotor && hdc shell aa start -a EntryAbility -b com.liasica.rotor
  hdc shell snapshot_display -f /data/local/tmp/r.jpeg && hdc file recv /data/local/tmp/r.jpeg /tmp/rotor-screen.jpeg
  ```
- 抓 console 日志：`hdc shell hilog -x | grep <PID> | grep JSAPP`
- 控件树与自动点击：`hdc shell uitest dumpLayout -p /data/local/tmp/l.json` 导出后按文字找坐标，`hdc shell uitest uiInput click x y` 点击；HDS 标题栏图标按钮没有文字，按 `SymbolGlyph` 位置定位
- 已装的应用签名与新包不一致时会报 `install sign info inconsistent`，只能卸载重装，真机上先导出备份

## ArkTS 注意
- 系统 API（router / promptAction / getContext）已弃用，统一通过 `this.getUIContext().getRouter() / .getPromptAction() / .getHostContext()` 调用
- HMAC：`cryptoFramework.createMac(algo)`（'SHA1' 不带 HMAC 前缀），`cryptoFramework.createSymKeyGenerator('HMAC')`
- Asset Kit：`Map<asset.Tag, asset.Value>` 用 `asset.AssetMap = new Map()`，value 直接传 `Uint8Array`，不要 `.buffer as object`
- 全屏窗口：EntryAbility.onWindowStageCreate 中 `setWindowLayoutFullScreen(true)`，页面根 `HdsNavigation` / `HdsNavDestination` 加 `.ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])`，标题栏配置 `enableComponentSafeArea: true` 让内容避让
- ArkTS 严格模式："Function may throw exceptions" warning 必须用 try/catch 清掉；rethrow 不能直接 `throw e`，要 `throw new Error(String(e))`
- 自定义组件的属性名不能与通用属性同名（如 `size`、`width`），否则报 not assignable
- 带参 @Builder 传给 @BuilderParam 写 `() => { this.X(a) }`；`bindMenu` 与 `navDestination` 传 builder 引用不加括号，`tabBar`、`bindSheet` 传 builder 调用加括号

## 关键文件
- `pages/Index.ets`：首页、路由表、底部悬浮栏、搜索态、导入备份
- `pages/EditPage.ets`：添加与编辑（含高级选项）
- `pages/ManagePage.ets`：多选编辑（批量删除、加密导出）
- `pages/AboutPage.ets`：关于
- `services/ScanService.ets`：扫码与 Google Authenticator 迁移导入
- `components/OtpCard.ets`、`IssuerAvatar.ets`、`ProgressRing.ets`、`PasswordSheet.ets`
