# rotor-harmonyos 项目规则

## 平台
- HarmonyOS NEXT，API 23（compatibleSdkVersion 6.1.0），ArkTS + ArkUI 声明式
- Bundle: `com.liasica.rotor`
- 包名前缀：`com.liasica.rotor`

## 设计来源
- Sketch 文件：`Authenticator 1217.sketch`（已在 sketch MCP `http://localhost:31126/mcp` 中打开）作为视觉设计参考。
- 大盘视觉（布局、字号、间距、颜色 token）尽量贴近 sketch；细节可结合 HarmonyOS 设计语言（沉浸光感、SurfaceMaterial、HdsTabs 等）合理调整，不要求 sketch 先更新。
- 图标素材优先从 sketch 导出 3x png（`scales: '3'`）放入 `entry/src/main/resources/base/media/`，再用 `Image($r('app.media.xxx'))` 引用；如 sketch 缺合适素材，可用 ArkUI 几何元素或 `SymbolGlyph` 自绘补齐。
- 沉浸光感场景下如果原素材带不透明实色背景（如蓝色 FAB 按钮），可保留原素材并跳过 `backgroundBlurStyle`——光感对实色 PNG 无视觉效果。

## 调试流程
- 开发完一个功能（commit 后）必须用 hdc 真机/模拟器验证：
  ```bash
  export PATH="/Users/liasica/Library/OpenHarmony/Sdk/23/toolchains:$PATH"
  hvigorw 编译 → hdc install -r → hdc shell aa force-stop com.liasica.rotor → hdc shell aa start -a EntryAbility -b com.liasica.rotor
  hdc shell snapshot_display -f /data/local/tmp/r.jpeg && hdc file recv /data/local/tmp/r.jpeg /tmp/rotor-screen.jpeg
  ```
- 抓 console 日志：`hdc shell hilog -x | grep <PID> | grep JSAPP`
- hdc 路径：`/Users/liasica/Library/OpenHarmony/Sdk/23/toolchains/hdc`
- 编译命令：`/Applications/DevEco-Studio.app/Contents/tools/node/bin/node /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw.js --mode module -p module=entry@default -p product=default -p requiredDeviceType=phone assembleHap --analyze=normal --parallel --incremental --daemon`

## ArkTS 注意
- 系统 API（router / promptAction / getContext）已弃用——统一通过 `this.getUIContext().getRouter() / .getPromptAction() / .getHostContext()` 调用
- HMAC：`cryptoFramework.createMac(algo)`（'SHA1' 不带 HMAC 前缀），`cryptoFramework.createSymKeyGenerator('HMAC')`
- Asset Kit：`Map<asset.Tag, asset.Value>` 用 `asset.AssetMap = new Map()`，value 直接传 `Uint8Array`，不要 `.buffer as object`
- 全屏窗口：EntryAbility.onWindowStageCreate 中 `windowStage.getMainWindowSync().setWindowLayoutFullScreen(true)`，page 根容器加 `.expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])`
- ArkTS 严格模式："Function may throw exceptions" warning 必须用 try/catch 清掉；rethrow 不能直接 `throw e`，要 `throw new Error(String(e))`

## 关键文件路径
- Sketch 中心 frame ID：
  - appicon: `1E024F09-F8E1-4EAB-962D-FACBD89F3631`
  - 首页 light: `807C53E8-55A0-4ABD-9F53-031BE290A783`
  - 首页 dark: `1439A902-17DF-4898-ACD4-A52E852FD4F0`
  - 编辑/添加 light: `FEE3020A-AFF5-48D7-8BC2-29988E25C64B`
  - 加号菜单 light: `350D412F-A718-447A-B849-D2F826926183`
  - 操作菜单 light: `B2821546-3D33-4FA3-861E-E3C02072C149`
  - 搜索 light: `985FB2A1-EF58-448B-89FE-09EE949BCDFD`
  - 弹出控件 light: `7B9212E3-B5B1-46BA-90F4-D842E56D64DB`
  - 导出验证码: `E482A51A-3119-44BC-A36E-972F0312A7BF`
  - 删除对话框: `14F2409D-0AB3-440F-8068-30E2F57B10E0`
  - 单条操作左滑 light: `1C8197AE-E381-4CDA-80CA-B6FCC729D35B`
  - 单条操作右滑 light: `670D271A-AE94-4693-AE98-7588420E351D`
- Spec：`docs/superpowers/specs/2026-04-25-authenticator-design.md`
- Plan：`docs/superpowers/plans/2026-04-25-authenticator-mvp.md`
