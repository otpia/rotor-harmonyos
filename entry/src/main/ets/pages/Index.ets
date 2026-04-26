import { pasteboard } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { OtpAccount, OtpType } from '../model/OtpAccount';
import { OtpAccountStore } from '../services/OtpAccountStore';
import { SecretVault } from '../services/SecretVault';
import { totp, hotp, remainingSeconds } from '../services/OtpEngine';
import { TickerService } from '../services/TickerService';
import { OtpItem } from '../components/OtpItem';
import { SearchBar } from '../components/SearchBar';
import { CopyToast } from '../components/CopyToast';
import { PlusMenuPopup } from '../components/PlusMenuPopup';
import { MoreMenuPopup } from '../components/MoreMenuPopup';
import { DeleteConfirmDialog } from '../components/DeleteConfirmDialog';
import { PageContainer } from '../components/PageContainer';

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
  @State moreOpen: boolean = false;
  @State pendingDeleteName: string = '';
  // 自增版本号，配合 ForEach key 在 onPageShow 时强制重建列表，重置 swipeAction 偏移
  @State listVersion: number = 0;
  private pendingDeleteId: string = '';
  private unsubTick: (() => void) | null = null;

  deleteDialog: CustomDialogController = new CustomDialogController({
    builder: DeleteConfirmDialog({
      name: this.pendingDeleteName,
      onConfirm: () => this.confirmDelete()
    }),
    alignment: DialogAlignment.Bottom,
    customStyle: true
  });

  aboutToAppear(): void {
    this.refresh();
    this.unsubTick = TickerService.subscribe((now: number) => this.tick(now));
  }

  aboutToDisappear(): void {
    if (this.unsubTick) this.unsubTick();
  }

  onPageShow(): void {
    this.listVersion++;
    this.refresh();
  }

  private async refresh(): Promise<void> {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
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
            } catch (_e) { code = '------'; }
          }
          next[a.id] = { code, remaining: a.period };
        } else {
          const remaining = remainingSeconds(now, a.period);
          if (sec && (!prev || remaining === a.period || prev.code === '------')) {
            try {
              code = await totp(sec, now, a.period, a.digits, a.algorithm);
            } catch (_e) { code = '------'; }
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
      if (!sec) return;
      a.counter += 1;
      a.updatedAt = Date.now();
      const code = await hotp(sec, a.counter, a.digits, a.algorithm);
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await OtpAccountStore.update(ctx, a);
      const next: Record<string, CodeState> = {};
      for (const k of Object.keys(this.codes)) next[k] = this.codes[k];
      next[a.id] = { code, remaining: a.period };
      this.codes = next;
    } catch (e) {
      console.error('[Index.refreshHotp]', e);
    }
  }

  private filtered(): OtpAccount[] {
    if (!this.query) return this.accounts;
    const q = this.query.toLowerCase();
    return this.accounts.filter((a: OtpAccount) =>
      a.name.toLowerCase().includes(q) || a.note.toLowerCase().includes(q));
  }

  private async copy(a: OtpAccount): Promise<void> {
    try {
      const c = this.codes[a.id];
      if (!c) return;
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, c.code);
      await pasteboard.getSystemPasteboard().setData(data);
      this.activeId = a.id;
      this.toastVisible = true;
      setTimeout(() => { this.toastVisible = false; }, 1500);
    } catch (e) {
      console.error('[Index.copy]', e);
    }
  }

  private askDelete(a: OtpAccount): void {
    this.pendingDeleteName = a.name;
    this.pendingDeleteId = a.id;
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
    try {
      if (!this.pendingDeleteId) return;
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const id = this.pendingDeleteId;
      await SecretVault.remove(id);
      await OtpAccountStore.delete(ctx, id);
      this.pendingDeleteId = '';
      this.pendingDeleteName = '';
      this.refresh();
    } catch (e) {
      console.error('[Index.confirmDelete]', e);
    }
  }

  private edit(a: OtpAccount): void {
    try {
      this.getUIContext().getRouter().pushUrl({ url: 'pages/EditPage', params: { id: a.id, prefilled: a } });
    } catch (e) {
      console.error('[Index.edit]', e);
    }
  }

  @Builder SwipeStart(a: OtpAccount) {
    Image($r('app.media.swipe_edit'))
      .width(40).height(40)
      .margin({ left: 8, right: 16 })
      .onClick(() => this.edit(a))
  }

  @Builder SwipeEnd(a: OtpAccount) {
    Image($r('app.media.swipe_delete'))
      .width(40).height(40)
      .margin({ left: 16, right: 8 })
      .onClick(() => this.askDelete(a))
  }

  private async handleImport(): Promise<void> {
    this.moreOpen = false;
    this.getUIContext().getRouter().pushUrl({ url: 'pages/ImportPage' });
  }

  @Builder PageBody() {
    Stack() {
      Column() {
        Row() {
          Blank()
          Image($r('app.media.more'))
            .width(24).height(24)
            .onClick(() => { this.moreOpen = !this.moreOpen; this.plusOpen = false; })
        }.width('100%').height(56).padding({ left: 16, right: 16 })

        SearchBar({ query: $query }).margin({ left: 24, right: 24, top: 8, bottom: 16 })

        if (this.accounts.length === 0) {
          Column() {
            Text($r('app.string.empty_hint'))
              .fontColor($r('app.color.text_secondary')).fontSize(14)
          }.layoutWeight(1).justifyContent(FlexAlign.Center).width('100%')
        } else {
          List({ space: 12 }) {
            ForEach(this.filtered(), (a: OtpAccount) => {
              ListItem() {
                OtpItem({
                  account: a,
                  code: this.codes[a.id] ? this.codes[a.id].code : '------',
                  remaining: this.codes[a.id] ? this.codes[a.id].remaining : a.period,
                  highlighted: this.activeId === a.id,
                  onTap: () => this.copy(a),
                  onRefresh: () => this.refreshHotp(a)
                })
              }
              .swipeAction({
                start: { builder: () => { this.SwipeStart(a) } },
                end: { builder: () => { this.SwipeEnd(a) } },
                edgeEffect: SwipeEdgeEffect.None
              })
            }, (a: OtpAccount) => `${a.id}-${this.listVersion}`)
          }
          .layoutWeight(1)
          .padding({ left: 24, right: 24, bottom: 16 })
        }
      }.width('100%').height('100%').backgroundColor($r('app.color.bg_app'))

      // 加号或更多菜单展开时的全屏透明遮罩，点击空白处自动收起
      if (this.plusOpen || this.moreOpen) {
        Column()
          .width('100%').height('100%')
          .backgroundColor(Color.Transparent)
          .onClick(() => { this.plusOpen = false; this.moreOpen = false; })
      }

      if (this.moreOpen) {
        Column() {
          MoreMenuPopup({
            onExport: () => {
              this.moreOpen = false;
              this.getUIContext().getRouter().pushUrl({ url: 'pages/ExportPage' });
            },
            onImport: () => { this.handleImport(); },
            onAbout: () => {
              this.moreOpen = false;
              this.getUIContext().getRouter().pushUrl({ url: 'pages/AboutPage' });
            }
          })
        }.position({ right: 16, top: 56 })
      }

      Column() {
        if (this.plusOpen) {
          PlusMenuPopup({
            onInputSecret: () => {
              this.plusOpen = false;
              this.getUIContext().getRouter().pushUrl({ url: 'pages/EditPage' });
            },
            onScanQr: () => {
              this.plusOpen = false;
              this.getUIContext().getRouter().pushUrl({ url: 'pages/ScanPage' });
            }
          })
            .margin({ bottom: 12 })
        }
        Image($r('app.media.fab_add'))
          .width(56).height(56)
          .onClick(() => { this.plusOpen = !this.plusOpen; })
      }
      .position({ right: 24, bottom: 24 })
      .alignItems(HorizontalAlign.End)

      if (this.toastVisible) {
        Column() {
          CopyToast({ visible: this.toastVisible })
        }.position({ bottom: 24 }).width('100%').alignItems(HorizontalAlign.Center)
      }
    }
    .width('100%').height('100%')
  }

  build() {
    Stack() {
      PageContainer({ content: () => { this.PageBody() } })
    }.width('100%').height('100%')
  }
}
