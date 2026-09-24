import { common, OpenLinkOptions } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { relationalStore } from '@kit.ArkData';
import { uiMaterial } from '@kit.ArkUI';
import { HdsNavDestination, hdsMaterial, ScrollEffectType } from '@kit.UIDesignKit';
import { CloudSyncService, CloudSyncState, CloudSyncStatus, syncStateSymbol } from '../services/CloudSyncService';
import { getString } from '../utils/I18n';

const CLOUD_SETTINGS_LINK = 'hicloud://cloudDrive/getInfo?path=MainActivity';
const ROW_HEIGHT = 56;

function dialogMaterial(): uiMaterial.ImmersiveMaterial {
  return new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.ULTRA_THICK });
}

// 云同步：状态、开关、立即同步、跳转系统云空间
@Component
export struct SyncPage {
  @State status: CloudSyncStatus = CloudSyncService.status();
  @State switchOn: boolean = CloudSyncService.isEnabled();
  @State busy: boolean = false;
  private scroller: Scroller = new Scroller();
  private unsubStatus: (() => void) | null = null;

  aboutToAppear(): void {
    this.unsubStatus = CloudSyncService.onStatusChange((s: CloudSyncStatus) => {
      this.status = s;
    });
  }

  aboutToDisappear(): void {
    if (this.unsubStatus) {
      this.unsubStatus();
    }
  }

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private toast(msg: ResourceStr): void {
    try {
      this.getUIContext().getPromptAction().showToast({
        message: msg,
        systemMaterial: new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.THICK })
      });
    } catch (e) {
      console.error('[SyncPage.toast]', e);
    }
  }

  private stateText(): Resource {
    const s = this.status;
    if (s.state === CloudSyncState.OFF) {
      return $r('app.string.sync_state_off');
    }
    if (s.state === CloudSyncState.SYNCING) {
      return $r('app.string.sync_state_syncing');
    }
    if (s.state === CloudSyncState.SYNCED) {
      return $r('app.string.sync_state_synced');
    }
    const c = s.code;
    if (!s.online || c === relationalStore.ProgressCode.NETWORK_ERROR) {
      return $r('app.string.sync_state_network');
    }
    if (c === relationalStore.ProgressCode.UNKNOWN_ERROR) {
      return $r('app.string.sync_state_paused');
    }
    if (c === relationalStore.ProgressCode.CLOUD_DISABLED) {
      return $r('app.string.sync_state_cloud_disabled');
    }
    if (c === relationalStore.ProgressCode.LOCKED_BY_OTHERS) {
      return $r('app.string.sync_state_locked');
    }
    if (c === relationalStore.ProgressCode.RECORD_LIMIT_EXCEEDED) {
      return $r('app.string.sync_state_limit');
    }
    if (c === relationalStore.ProgressCode.NO_SPACE_FOR_ASSET) {
      return $r('app.string.sync_state_no_space');
    }
    if (c === relationalStore.ProgressCode.BLOCKED_BY_NETWORK_STRATEGY) {
      return $r('app.string.sync_state_strategy');
    }
    if (c === relationalStore.ProgressCode.STOP_CLOUD_SYNC) {
      return $r('app.string.sync_state_stopped');
    }
    return $r('app.string.sync_state_failed');
  }

  // 最近同步时间，格式为 YYYY-MM-DD HH:mm:ss
  private lastSyncText(): string {
    const d = new Date(this.status.lastSyncAt);
    const pad = (n: number): string => n < 10 ? '0' + String(n) : String(n);
    const time = `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ` +
      `${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
    return getString(this.ctx(), 'sync_last_time', time);
  }

  // 程序回写 switchOn 时也会触发，按服务的实际状态判断是否需要动作
  private onToggle(isOn: boolean): void {
    if (this.busy) {
      return;
    }
    if (isOn && !CloudSyncService.isEnabled()) {
      this.turnOn();
    } else if (!isOn && CloudSyncService.isEnabled()) {
      this.askTurnOff();
    }
  }

  private async turnOn(): Promise<void> {
    const ctx = this.ctx();
    this.busy = true;
    try {
      await CloudSyncService.enable(ctx);
      if (!(await CloudSyncService.guideShown(ctx))) {
        await CloudSyncService.markGuideShown(ctx);
        this.showGuide();
      }
    } catch (e) {
      console.error('[SyncPage.turnOn]', e);
      this.switchOn = false;
      this.toast($r('app.string.toast_sync_enable_failed'));
    } finally {
      this.busy = false;
    }
  }

  private askTurnOff(): void {
    try {
      this.getUIContext().showAlertDialog({
        message: $r('app.string.sync_disable_confirm'),
        systemMaterial: dialogMaterial(),
        primaryButton: {
          value: $r('app.string.btn_cancel'),
          action: () => {
            this.switchOn = true;
          }
        },
        secondaryButton: {
          value: $r('app.string.btn_turn_off'),
          fontColor: $r('sys.color.warning'),
          action: () => {
            this.turnOff();
          }
        },
        cancel: () => {
          this.switchOn = true;
        }
      });
    } catch (e) {
      console.error('[SyncPage.askTurnOff]', e);
      this.switchOn = true;
    }
  }

  private async turnOff(): Promise<void> {
    this.busy = true;
    try {
      await CloudSyncService.disable(this.ctx());
    } catch (e) {
      console.error('[SyncPage.turnOff]', e);
      this.switchOn = true;
      this.toast($r('app.string.toast_sync_disable_failed'));
    } finally {
      this.busy = false;
    }
  }

  private showGuide(): void {
    try {
      this.getUIContext().showAlertDialog({
        message: $r('app.string.sync_enable_dialog'),
        systemMaterial: dialogMaterial(),
        primaryButton: {
          value: $r('app.string.btn_later'),
          action: () => {
          }
        },
        secondaryButton: {
          value: $r('app.string.btn_go_enable'),
          action: () => {
            this.openCloudSettings();
          }
        }
      });
    } catch (e) {
      console.error('[SyncPage.showGuide]', e);
    }
  }

  private openCloudSettings(): void {
    try {
      const opts: OpenLinkOptions = { appLinkingOnly: false };
      this.ctx().openLink(CLOUD_SETTINGS_LINK, opts).catch((e: BusinessError) => {
        console.error('[SyncPage.openCloudSettings]', e.code, e.message);
      });
    } catch (e) {
      console.error('[SyncPage.openCloudSettings]', e);
    }
  }

  @Styles cardStyle() {
    .backgroundColor($r('sys.color.comp_background_list_card'))
    .borderRadius($r('sys.float.corner_radius_level8'))
    .width('100%')
  }

  @Builder StatusCard() {
    Column() {
      Row() {
        SymbolGlyph(syncStateSymbol(this.status.state))
          .fontSize(32)
          .fontColor([$r('sys.color.icon_primary')])
        Column() {
          Text(this.stateText())
            .fontSize($r('sys.float.Body_L'))
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary'))
          if (this.status.lastSyncAt > 0) {
            Text(this.lastSyncText())
              .fontSize($r('sys.float.Body_M'))
              .fontColor($r('sys.color.font_secondary'))
              .margin({ top: 2 })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .margin({ left: 12 })
      }
      .width('100%')
      .padding(16)
      .alignItems(VerticalAlign.Center)

      if (this.status.state !== CloudSyncState.OFF) {
        Column() {
          Button($r('app.string.sync_now'))
            .buttonStyle(ButtonStyleMode.NORMAL)
            .width('100%')
            .enabled(this.status.state !== CloudSyncState.SYNCING)
            .onClick(() => {
              CloudSyncService.syncNow(this.ctx(), true);
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 16 })
      }
    }
    .cardStyle()
  }

  @Builder SwitchCard() {
    Row() {
      Text($r('app.string.sync_switch'))
        .fontSize($r('sys.float.Body_L'))
        .fontColor($r('sys.color.font_primary'))
        .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: $$this.switchOn })
        .enabled(!this.busy)
        .onChange((isOn: boolean) => {
          this.onToggle(isOn);
        })
    }
    .width('100%')
    .height(ROW_HEIGHT)
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
    .cardStyle()
  }

  @Builder SettingsCard() {
    Row() {
      Text($r('app.string.sync_cloud_settings'))
        .fontSize($r('sys.float.Body_L'))
        .fontColor($r('sys.color.font_primary'))
        .layoutWeight(1)
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(20)
        .fontColor([$r('sys.color.icon_secondary')])
    }
    .width('100%')
    .height(ROW_HEIGHT)
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
    .cardStyle()
    .onClick(() => {
      this.openCloudSettings();
    })
  }

  build() {
    HdsNavDestination() {
      Scroll(this.scroller) {
        Column({ space: 12 }) {
          this.StatusCard()
          this.SwitchCard()
          this.SettingsCard()
          Text($r('app.string.sync_description'))
            .fontSize($r('sys.float.Body_M'))
            .fontColor($r('sys.color.font_secondary'))
            .lineHeight(22)
            .width('100%')
            .padding({ left: 16, right: 16, top: 4 })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 24 })
      }
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .width('100%')
      .height('100%')
    }
    .backgroundColor($r('sys.color.background_secondary'))
    .titleBar({
      content: {
        title: { mainTitle: $r('app.string.sync_title') }
      },
      style: {
        scrollEffectOpts: {
          enableScrollEffect: true,
          scrollEffectType: ScrollEffectType.GRADIENT_BLUR
        },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        }
      },
      avoidLayoutSafeArea: true,
      enableComponentSafeArea: true
    })
    .bindToScrollable([this.scroller])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
  }
}
