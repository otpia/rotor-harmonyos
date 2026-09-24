import { BusinessError, pasteboard } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import { vibrator } from '@kit.SensorServiceKit';
import { curves, KeyboardAvoidMode, SymbolGlyphModifier, uiMaterial } from '@kit.ArkUI';
import {
  HdsAnimationMode,
  HdsNavigation,
  HdsNavigationTitleMode,
  HdsTabs,
  HdsTabsController,
  hdsMaterial,
  ScrollEffectType
} from '@kit.UIDesignKit';
import { OtpAccount, OtpType } from '../model/OtpAccount';
import { OtpAccountStore } from '../services/OtpAccountStore';
import { SecretVault } from '../services/SecretVault';
import { totp, hotp, remainingSeconds } from '../services/OtpEngine';
import { TickerService } from '../services/TickerService';
import { importBackup } from '../services/BackupImporter';
import { scanQrCode, ScanResult, ScanResultKind } from '../services/ScanService';
import { getString } from '../utils/I18n';
import { OtpCard } from '../components/OtpCard';
import { PasswordSheet } from '../components/PasswordSheet';
import { EditPage, EditParams } from './EditPage';
import { ManagePage } from './ManagePage';
import { AboutPage } from './AboutPage';

interface CodeState {
  code: string;
  remaining: number;
}

const ROUTE_EDIT = 'edit';
const ROUTE_MANAGE = 'manage';
const ROUTE_ABOUT = 'about';
const SEARCH_ID = 'rotor_search_input';
// 底部悬浮栏高度加留白，列表末尾预留，避免最后一项被遮挡
const LIST_END_OFFSET = 108;
// 列表左右留白下限
const LIST_SIDE_MARGIN = 16;
// 拖拽浮起时框架固定把 ListItem 放大 1.05 倍，宽屏下留白需随列表宽度加大，保证浮起后卡片离屏幕边缘至少 8vp
const LIFT_SCALE = 1.05;
const LIFT_EDGE_GAP = 8;

// 弹出层沉浸式材质：菜单用厚材质并自动反色，弹窗与半模态用超厚材质
function menuMaterial(): uiMaterial.ImmersiveMaterial {
  return new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.THICK, colorInvert: true });
}

function dialogMaterial(): uiMaterial.ImmersiveMaterial {
  return new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.ULTRA_THICK });
}

// 长按浮起的触感反馈，与系统组件长按同款效果；设备不支持时退回通用轻振
const LONG_PRESS_HAPTIC = 'haptic.long_press_light';

function liftHaptic(): void {
  try {
    const effectId = vibrator.isSupportEffectSync(LONG_PRESS_HAPTIC) ? LONG_PRESS_HAPTIC : 'haptic.effect.soft';
    vibrator.startVibration({ type: 'preset', effectId: effectId, count: 1 }, { usage: 'touch' })
      .catch((e: BusinessError) => {
        console.error('[liftHaptic]', e.code, e.message);
      });
  } catch (e) {
    console.error('[liftHaptic]', e);
  }
}

@Entry
@Component
struct Index {
  @Provide('pathStack') pathStack: NavPathStack = new NavPathStack();
  @State accounts: OtpAccount[] = [];
  @State codes: Record<string, CodeState> = {};
  @State secrets: Record<string, string> = {};
  @State query: string = '';
  @State importSheetOpen: boolean = false;
  @State searchMode: boolean = false;
  @State listWidth: number = 0;
  @StorageProp('bottomSafeAreaPx') bottomSafeAreaPx: number = 0;
  private listScroller: ListScroller = new ListScroller();
  private tabsController: HdsTabsController = new HdsTabsController();
  private pendingImportUri: string = '';
  private unsubTick: (() => void) | null = null;

  aboutToAppear(): void {
    this.refresh();
    this.unsubTick = TickerService.subscribe((now: number) => this.tick(now));
    // 软键盘弹出时压缩页面而不是整体上移，保证标题栏与悬浮栏都留在可视区
    try {
      this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
    } catch (e) {
      console.error('[Index.setKeyboardAvoidMode]', e);
    }
    // 从任意二级页回到导航根时刷新列表并收起横滑
    try {
      this.pathStack.setInterception({
        didShow: (_from: NavDestinationContext | NavBar, to: NavDestinationContext | NavBar) => {
          if (typeof to === 'string') {
            this.onReturnHome();
          }
        }
      });
    } catch (e) {
      console.error('[Index.setInterception]', e);
    }
  }

  aboutToDisappear(): void {
    if (this.unsubTick) {
      this.unsubTick();
    }
  }

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private toast(msg: ResourceStr): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: msg, systemMaterial: menuMaterial() });
    } catch (e) {
      console.error('[Index.toast]', e);
    }
  }

  // ---------- 数据 ----------

  private async refresh(): Promise<void> {
    try {
      const ctx = this.ctx();
      this.accounts = await OtpAccountStore.listAll(ctx);
      for (const a of this.accounts) {
        if (!this.secrets[a.id]) {
          this.secrets[a.id] = await SecretVault.get(a.id);
        }
      }
      await this.tick(Date.now());
    } catch (e) {
      console.error('[Index.refresh]', e);
    }
  }

  private async tick(now: number): Promise<void> {
    try {
      const next: Record<string, CodeState> = {};
      for (const a of this.accounts) {
        const prev = this.codes[a.id];
        let code = prev ? prev.code : '------';
        const sec = this.secrets[a.id];
        if (a.type === OtpType.HOTP) {
          if (sec && (!prev || prev.code === '------')) {
            try {
              code = await hotp(sec, a.counter, a.digits, a.algorithm);
            } catch (_e) {
              code = '------';
            }
          }
          next[a.id] = { code, remaining: a.period };
        } else {
          const remaining = remainingSeconds(now, a.period);
          if (sec && (!prev || remaining === a.period || prev.code === '------')) {
            try {
              code = await totp(sec, now, a.period, a.digits, a.algorithm);
            } catch (_e) {
              code = '------';
            }
          }
          next[a.id] = { code, remaining };
        }
      }
      this.codes = next;
    } catch (e) {
      console.error('[Index.tick]', e);
    }
  }

  private async refreshHotp(a: OtpAccount): Promise<void> {
    try {
      const sec = this.secrets[a.id];
      if (!sec) {
        return;
      }
      a.counter += 1;
      a.updatedAt = Date.now();
      const code = await hotp(sec, a.counter, a.digits, a.algorithm);
      await OtpAccountStore.update(this.ctx(), a);
      const next: Record<string, CodeState> = {};
      for (const k of Object.keys(this.codes)) {
        next[k] = this.codes[k];
      }
      next[a.id] = { code, remaining: a.period };
      this.codes = next;
    } catch (e) {
      console.error('[Index.refreshHotp]', e);
    }
  }

  private filtered(): OtpAccount[] {
    if (this.query.length === 0) {
      return this.accounts;
    }
    const q = this.query.toLowerCase();
    return this.accounts.filter((a: OtpAccount) =>
      a.name.toLowerCase().includes(q) || a.note.toLowerCase().includes(q));
  }

  private async copy(a: OtpAccount): Promise<void> {
    try {
      const c = this.codes[a.id];
      if (!c) {
        return;
      }
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, c.code);
      await pasteboard.getSystemPasteboard().setData(data);
      this.toast($r('app.string.toast_copied'));
    } catch (e) {
      console.error('[Index.copy]', e);
    }
  }

  // 浮起后卡片每侧超出 `(列表宽 - 2 * 留白) * (LIFT_SCALE - 1) / 2`，据此反解留白
  private sideMargin(): number {
    const m = (LIFT_EDGE_GAP + this.listWidth * (LIFT_SCALE - 1) / 2) / LIFT_SCALE;
    return Math.max(LIST_SIDE_MARGIN, Math.ceil(m));
  }

  // 拖拽排序按 id 定位，兼容搜索过滤后的可见索引
  private async reorder(from: number, to: number): Promise<void> {
    try {
      const view = this.filtered();
      if (from < 0 || to < 0 || from >= view.length || to >= view.length || from === to) {
        return;
      }
      const movedId = view[from].id;
      const targetId = view[to].id;
      let moved: OtpAccount | null = null;
      const arr: OtpAccount[] = [];
      for (const a of this.accounts) {
        if (a.id === movedId) {
          moved = a;
        } else {
          arr.push(a);
        }
      }
      if (moved === null) {
        return;
      }
      let targetIndex = -1;
      for (let i = 0; i < arr.length; i++) {
        if (arr[i].id === targetId) {
          targetIndex = i;
          break;
        }
      }
      if (targetIndex < 0) {
        return;
      }
      arr.splice(from < to ? targetIndex + 1 : targetIndex, 0, moved);
      const now = Date.now();
      for (let i = 0; i < arr.length; i++) {
        arr[i].orderIndex = i + 1;
        arr[i].updatedAt = now;
      }
      this.accounts = arr;
      const ctx = this.ctx();
      for (const a of arr) {
        try {
          await OtpAccountStore.update(ctx, a);
        } catch (e) {
          console.error('[Index.reorder.update]', e);
        }
      }
    } catch (e) {
      console.error('[Index.reorder]', e);
    }
  }

  private askDelete(a: OtpAccount): void {
    try {
      this.getUIContext().showAlertDialog({
        message: getString(this.ctx(), 'delete_confirm_message', a.name),
        systemMaterial: dialogMaterial(),
        primaryButton: {
          value: $r('app.string.btn_cancel'),
          action: () => {
            this.listScroller.closeAllSwipeActions();
          }
        },
        secondaryButton: {
          value: $r('app.string.btn_delete'),
          fontColor: $r('sys.color.warning'),
          action: () => {
            this.confirmDelete(a.id);
          }
        },
        cancel: () => {
          this.listScroller.closeAllSwipeActions();
        }
      });
    } catch (e) {
      console.error('[Index.askDelete]', e);
    }
  }

  private async confirmDelete(id: string): Promise<void> {
    try {
      await SecretVault.remove(id);
      await OtpAccountStore.delete(this.ctx(), id);
      this.refresh();
    } catch (e) {
      console.error('[Index.confirmDelete]', e);
    }
  }

  // ---------- 路由 ----------

  private onReturnHome(): void {
    this.refresh();
    try {
      this.listScroller.closeAllSwipeActions();
    } catch (e) {
      console.error('[Index.onReturnHome]', e);
    }
  }

  private pushEdit(p: EditParams): void {
    try {
      this.pathStack.pushPathByName(ROUTE_EDIT, p);
    } catch (e) {
      console.error('[Index.pushEdit]', e);
    }
  }

  private edit(a: OtpAccount): void {
    const p: EditParams = { id: a.id, prefilled: a };
    this.pushEdit(p);
  }

  private addManually(): void {
    const p: EditParams = {};
    this.pushEdit(p);
  }

  private async addByScan(): Promise<void> {
    const ctx = this.ctx();
    const r: ScanResult = await scanQrCode(ctx);
    const parsed = r.parsed;
    if (r.kind === ScanResultKind.SINGLE && parsed !== null) {
      const p: EditParams = { prefilled: parsed.account, prefilledSecret: parsed.secret };
      this.pushEdit(p);
    } else if (r.kind === ScanResultKind.IMPORTED) {
      this.toast(getString(ctx, 'toast_imported_count', r.importedCount));
      this.refresh();
    } else if (r.kind === ScanResultKind.PERMISSION_DENIED) {
      this.toast($r('app.string.toast_camera_required'));
    } else if (r.kind === ScanResultKind.UNRECOGNIZED) {
      this.toast($r('app.string.toast_qr_unrecognized'));
    } else if (r.kind === ScanResultKind.NO_ACCOUNT) {
      this.toast($r('app.string.toast_qr_no_account'));
    }
  }

  private goManage(): void {
    try {
      this.pathStack.pushPathByName(ROUTE_MANAGE, ROUTE_MANAGE);
    } catch (e) {
      console.error('[Index.goManage]', e);
    }
  }

  private goAbout(): void {
    try {
      this.pathStack.pushPathByName(ROUTE_ABOUT, ROUTE_ABOUT);
    } catch (e) {
      console.error('[Index.goAbout]', e);
    }
  }

  // ---------- 导入备份 ----------

  private async handleImport(): Promise<void> {
    try {
      const docPicker = new picker.DocumentViewPicker(this.ctx());
      const opts: picker.DocumentSelectOptions = { maxSelectNumber: 1 };
      const uris = await docPicker.select(opts);
      if (!uris || uris.length === 0) {
        return;
      }
      this.pendingImportUri = uris[0];
      this.importSheetOpen = true;
    } catch (e) {
      console.error('[Index.handleImport]', e);
    }
  }

  private async runImport(password: string): Promise<void> {
    this.importSheetOpen = false;
    if (this.pendingImportUri.length === 0) {
      return;
    }
    const ctx = this.ctx();
    try {
      const count = await importBackup(ctx, this.pendingImportUri, password);
      this.toast(getString(ctx, 'toast_imported_count', count));
      this.pendingImportUri = '';
      this.refresh();
    } catch (e) {
      console.error('[Index.runImport]', e);
      this.toast($r('app.string.toast_import_failed'));
    }
  }

  // ---------- 搜索 ----------

  // 悬浮栏收起，底部原位换成搜索框并聚焦
  private enterSearch(): void {
    this.searchMode = true;
    try {
      this.tabsController.applyHideAnimation(HdsAnimationMode.CLICK_ANIMATION);
    } catch (e) {
      console.error('[Index.enterSearch] hide bar', e);
    }
    setTimeout(() => {
      try {
        this.getUIContext().getFocusController().requestFocus(SEARCH_ID);
      } catch (e) {
        console.error('[Index.enterSearch] focus', e);
      }
    }, 200);
  }

  private exitSearch(): void {
    this.query = '';
    this.searchMode = false;
    try {
      this.tabsController.applyShowAnimation(HdsAnimationMode.CLICK_ANIMATION);
    } catch (e) {
      console.error('[Index.exitSearch] show bar', e);
    }
  }

  // ---------- 构建器 ----------

  @Builder AddMenu() {
    Menu() {
      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.qrcode')),
        content: $r('app.string.menu_scan_qr')
      })
        .onClick(() => {
          this.addByScan();
        })
      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.keyboard')),
        content: $r('app.string.menu_input_secret')
      })
        .onClick(() => {
          this.addManually();
        })
    }
  }

  @Builder MoreMenu() {
    Menu() {
      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.square_and_arrow_down')),
        content: $r('app.string.menu_import')
      })
        .onClick(() => {
          this.handleImport();
        })
      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.square_and_pencil')),
        content: $r('app.string.btn_edit')
      })
        .onClick(() => {
          this.goManage();
        })
      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.info_circle')),
        content: $r('app.string.menu_about')
      })
        .onClick(() => {
          this.goAbout();
        })
    }
  }

  @Builder BarIcon(icon: Resource, label: Resource) {
    SymbolGlyph(icon)
      .fontSize(24)
      .fontColor([$r('sys.color.icon_primary')])
    Text(label)
      .fontSize($r('sys.float.Caption_M'))
      .fontColor($r('sys.color.font_primary'))
      .margin({ top: 2 })
  }

  @Builder SearchTab() {
    Column() {
      this.BarIcon($r('sys.symbol.magnifyingglass'), $r('app.string.bar_search'))
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.enterSearch();
    })
  }

  // 搜索态：替代悬浮栏出现在底部，与悬浮栏同为毛玻璃胶囊，键盘弹出时随页面压缩贴在键盘上方
  @Builder SearchBarRow() {
    Row() {
      SymbolGlyph($r('sys.symbol.magnifyingglass'))
        .fontSize(22)
        .fontColor([$r('sys.color.icon_secondary')])
        .margin({ left: 16, right: 8 })
      TextInput({ text: this.query, placeholder: $r('app.string.search_placeholder') })
        .id(SEARCH_ID)
        .height(56)
        .layoutWeight(1)
        .fontSize($r('sys.float.Body_L'))
        .backgroundColor(Color.Transparent)
        .padding({ left: 0, right: 0 })
        .enterKeyType(EnterKeyType.Search)
        .onChange((v: string) => {
          this.query = v;
        })
        .onSubmit(() => {
          try {
            this.getUIContext().getFocusController().clearFocus();
          } catch (e) {
            console.error('[Index.SearchBarRow] clearFocus', e);
          }
        })
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(20)
          .fontColor([$r('sys.color.icon_primary')])
      }
      .width(40)
      .height(40)
      .backgroundColor($r('sys.color.comp_background_tertiary'))
      .margin({ right: 8 })
      .onClick(() => {
        this.exitSearch();
      })
    }
    .height(56)
    .margin({
      left: 16,
      right: 16,
      bottom: Math.max(this.getUIContext().px2vp(this.bottomSafeAreaPx), 16)
    })
    .borderRadius(28)
    .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
    .shadow(ShadowStyle.OUTER_DEFAULT_SM)
    .alignItems(VerticalAlign.Center)
    .transition(TransitionEffect.asymmetric(
      TransitionEffect.move(TransitionEdge.BOTTOM)
        .combine(TransitionEffect.scale({ x: 0.85, y: 0.85 }))
        .combine(TransitionEffect.opacity(0))
        .animation({ curve: curves.interpolatingSpring(0, 1, 200, 17) }),
      TransitionEffect.move(TransitionEdge.BOTTOM)
        .combine(TransitionEffect.opacity(0))
        .animation({ curve: curves.interpolatingSpring(0, 1, 170, 17) })
    ))
  }

  @Builder AddTab() {
    Column() {
      this.BarIcon($r('sys.symbol.plus'), $r('app.string.bar_add'))
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .bindMenu(this.AddMenu, { placement: Placement.Top, systemMaterial: menuMaterial() })
  }

  @Builder MoreTab() {
    Column() {
      this.BarIcon($r('sys.symbol.dot_grid_2x2'), $r('app.string.bar_more'))
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .bindMenu(this.MoreMenu, { placement: Placement.Top, systemMaterial: menuMaterial() })
  }

  @Builder ImportSheet() {
    PasswordSheet({
      needConfirm: false,
      placeholder: $r('app.string.import_password_hint'),
      submitLabel: $r('app.string.btn_import'),
      onSubmit: (pwd: string) => {
        this.runImport(pwd);
      }
    })
  }

  @Builder SwipeCircle(icon: Resource, bg: Resource, onTap: () => void) {
    Column() {
      SymbolGlyph(icon)
        .fontSize(20)
        .fontColor([$r('sys.color.icon_on_primary')])
    }
    .width(40)
    .height(40)
    .borderRadius(20)
    .backgroundColor(bg)
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      onTap();
    })
  }

  // 左滑露出的编辑与删除按钮
  @Builder SwipeActions(a: OtpAccount) {
    Row({ space: 12 }) {
      this.SwipeCircle($r('sys.symbol.square_and_pencil'), $r('sys.color.alert'), () => {
        this.edit(a);
      })
      this.SwipeCircle($r('sys.symbol.trash'), $r('sys.color.warning'), () => {
        this.askDelete(a);
      })
    }
    .height('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ left: 12 })
  }

  @Builder CardBuilder(a: OtpAccount) {
    OtpCard({
      account: a,
      code: this.codes[a.id] ? this.codes[a.id].code : '------',
      remaining: this.codes[a.id] ? this.codes[a.id].remaining : a.period,
      onRefresh: () => {
        this.refreshHotp(a);
      }
    })
      .onClick(() => {
        this.copy(a);
      })
  }

  @Builder ListArea() {
    if (this.accounts.length === 0) {
      Column() {
        SymbolGlyph($r('sys.symbol.key'))
          .fontSize(48)
          .fontColor([$r('sys.color.icon_tertiary')])
        Text($r('app.string.empty_hint'))
          .fontSize($r('sys.float.Body_M'))
          .fontColor($r('sys.color.font_secondary'))
          .margin({ top: 12 })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    } else {
      List({ space: 12, scroller: this.listScroller }) {
        ForEach(this.filtered(), (a: OtpAccount) => {
          ListItem() {
            this.CardBuilder(a)
          }
          // 拖拽浮起时框架把 ListItem 放大并按其圆角画阴影：圆角需与卡片一致，
          // 左右留白放在 ListItem 上而不是 List 的 padding，否则放大后的卡片会被 List 内容区裁掉
          .borderRadius($r('sys.float.corner_radius_level8'))
          .margin({ left: this.sideMargin(), right: this.sideMargin() })
          .swipeAction({
            end: {
              builder: () => {
                this.SwipeActions(a);
              }
            },
            edgeEffect: SwipeEdgeEffect.None
          })
        }, (a: OtpAccount) => a.id)
          .onMove((from: number, to: number) => {
            this.reorder(from, to);
          }, {
            onLongPress: () => {
              liftHaptic();
            }
          })
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .contentEndOffset(LIST_END_OFFSET)
      .clipContent(ContentClipMode.SAFE_AREA)
      .onAreaChange((_old: Area, area: Area) => {
        this.listWidth = Number(area.width);
      })
    }
  }

  @Builder PageMap(name: string, param: Object) {
    if (name === ROUTE_EDIT) {
      EditPage({ params: param as EditParams })
    } else if (name === ROUTE_MANAGE) {
      ManagePage()
    } else if (name === ROUTE_ABOUT) {
      AboutPage()
    }
  }

  build() {
    HdsNavigation(this.pathStack) {
      Stack({ alignContent: Alignment.Bottom }) {
        HdsTabs({ controller: this.tabsController }) {
          TabContent() {
            this.ListArea()
          }
          .tabBar(this.SearchTab())

          TabContent() {
            Column()
          }
          .tabBar(this.AddTab())

          TabContent() {
            Column()
          }
          .tabBar(this.MoreTab())
        }
        .width('100%')
        .height('100%')
        .barOverlap(true)
        .vertical(false)
        .barPosition(BarPosition.End)
        .scrollable(false)
        .barFloatingStyle({
          adaptToHandedness: true,
          barBottomMargin: this.bottomSafeAreaPx > 0 ? this.getUIContext().px2vp(this.bottomSafeAreaPx) : 16,
          systemMaterialEffect: {
            materialType: hdsMaterial.MaterialType.ADAPTIVE,
            materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
          }
        })
        .onContentWillChange((_current: number, _coming: number) => false)

        if (this.searchMode) {
          this.SearchBarRow()
        }
      }
      .width('100%')
      .height('100%')
    }
    .mode(NavigationMode.Stack)
    .backgroundColor($r('sys.color.background_secondary'))
    .titleMode(HdsNavigationTitleMode.FREE)
    .hideBackButton(true)
    .titleBar({
      content: {
        title: { mainTitle: $r('app.string.EntryAbility_label') }
      },
      style: {
        scrollEffectOpts: {
          enableScrollEffect: true,
          scrollEffectType: ScrollEffectType.GRADIENT_BLUR
        },
        originalStyle: {
          contentStyle: {
            titleStyle: { mainTitleColor: $r('sys.color.font_primary') }
          }
        },
        scrollEffectStyle: {
          contentStyle: {
            titleStyle: { mainTitleColor: $r('sys.color.font_primary') }
          }
        },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        }
      },
      avoidLayoutSafeArea: true,
      enableComponentSafeArea: true
    })
    .bindToScrollable([this.listScroller])
    .navDestination(this.PageMap)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .bindSheet($$this.importSheetOpen, this.ImportSheet(), {
      systemMaterial: dialogMaterial(),
      detents: [SheetSize.FIT_CONTENT],
      title: { title: $r('app.string.import_password_hint') },
      showClose: true,
      preferType: SheetType.BOTTOM
    })
  }
}
