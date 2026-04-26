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
  @State toastVisible: boolean = false;
  @State plusOpen: boolean = false;
  @State moreOpen: boolean = false;
  @State pendingDeleteName: string = '';
  // 自增版本号，配合 ForEach key 在 onPageShow 时强制重建列表，重置 swipeAction 偏移
  @State listVersion: number = 0;
  // 编辑模式：长按卡片进入，可多选删除/拖拽排序
  @State editMode: boolean = false;
  @State multiSelected: Record<string, boolean> = {};
  // 拖拽排序时的源 index，用于浮层 builder
  @State dragSource: number = -1;
  private pendingDeleteId: string = '';
  private unsubTick: (() => void) | null = null;

  deleteDialog: CustomDialogController = new CustomDialogController({
    builder: DeleteConfirmDialog({
      name: this.pendingDeleteName,
      onConfirm: () => this.confirmDelete()
    }),
    alignment: DialogAlignment.Bottom,
    customStyle: true,
    maskColor: $r('app.color.scrim')
  });

  multiDeleteDialog: CustomDialogController = new CustomDialogController({
    builder: DeleteConfirmDialog({
      name: '',
      onConfirm: () => this.confirmMultiDelete()
    }),
    alignment: DialogAlignment.Bottom,
    customStyle: true,
    maskColor: $r('app.color.scrim')
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
      customStyle: true,
      maskColor: $r('app.color.scrim')
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

  private enterEditMode(initialId: string): void {
    if (this.editMode) return;
    const sel: Record<string, boolean> = {};
    for (const a of this.accounts) sel[a.id] = a.id === initialId;
    this.multiSelected = sel;
    this.editMode = true;
    this.plusOpen = false;
    this.moreOpen = false;
  }

  private exitEditMode(): void {
    this.editMode = false;
    this.multiSelected = {};
  }

  private toggleSelected(id: string): void {
    const next: Record<string, boolean> = {};
    for (const k of Object.keys(this.multiSelected)) next[k] = this.multiSelected[k];
    next[id] = !next[id];
    this.multiSelected = next;
  }

  private selectedCount(): number {
    let n = 0;
    for (const a of this.accounts) if (this.multiSelected[a.id]) n++;
    return n;
  }

  private askMultiDelete(): void {
    const n = this.selectedCount();
    if (n === 0) return;
    this.multiDeleteDialog = new CustomDialogController({
      builder: DeleteConfirmDialog({
        name: `${n} 个账号`,
        onConfirm: () => this.confirmMultiDelete()
      }),
      alignment: DialogAlignment.Bottom,
      customStyle: true,
      maskColor: $r('app.color.scrim')
    });
    this.multiDeleteDialog.open();
  }

  private async reorder(from: number, to: number): Promise<void> {
    try {
      if (from < 0 || to < 0 || from >= this.accounts.length) return;
      const target = to > from ? to - 1 : to;
      if (target === from || target < 0 || target >= this.accounts.length) return;
      const arr: OtpAccount[] = [];
      for (const a of this.accounts) arr.push(a);
      const moved = arr.splice(from, 1)[0];
      arr.splice(target, 0, moved);
      const now = Date.now();
      for (let i = 0; i < arr.length; i++) {
        arr[i].orderIndex = i + 1;
        arr[i].updatedAt = now;
      }
      this.accounts = arr;
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
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

  private async confirmMultiDelete(): Promise<void> {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const ids: string[] = [];
      for (const a of this.accounts) if (this.multiSelected[a.id]) ids.push(a.id);
      for (const id of ids) {
        try {
          await SecretVault.remove(id);
          await OtpAccountStore.delete(ctx, id);
        } catch (e) {
          console.error('[Index.confirmMultiDelete.item]', e);
        }
      }
      this.exitEditMode();
      this.refresh();
    } catch (e) {
      console.error('[Index.confirmMultiDelete]', e);
    }
  }

  @Builder DragPreview() {
    if (this.dragSource >= 0 && this.dragSource < this.accounts.length) {
      Column() {
        OtpItem({
          account: this.accounts[this.dragSource],
          code: this.codes[this.accounts[this.dragSource].id]
            ? this.codes[this.accounts[this.dragSource].id].code
            : '------',
          remaining: this.codes[this.accounts[this.dragSource].id]
            ? this.codes[this.accounts[this.dragSource].id].remaining
            : this.accounts[this.dragSource].period,
          editMode: false,
          selected: false
        })
      }
      .opacity(0.92)
      .padding({ left: 24, right: 24 })
      .width('100%')
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
        if (this.editMode) {
          Row() {
            Text($r('app.string.btn_cancel'))
              .fontSize(16).fontColor($r('app.color.accent_blue'))
              .padding({ left: 4, right: 4, top: 8, bottom: 8 })
              .onClick(() => this.exitEditMode())
            Blank()
            Text(`已选 ${this.selectedCount()} 项`)
              .fontSize(16).fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
            Blank()
            Text($r('app.string.btn_delete'))
              .fontSize(16).fontWeight(FontWeight.Medium)
              .fontColor(this.selectedCount() > 0 ? $r('app.color.accent_red') : $r('app.color.text_secondary'))
              .padding({ left: 4, right: 4, top: 8, bottom: 8 })
              .onClick(() => this.askMultiDelete())
          }.width('100%').height(56).padding({ left: 16, right: 16 })
            .alignItems(VerticalAlign.Center)
        } else {
          Row() {
            Blank()
            Image($r('app.media.more'))
              .width(24).height(24)
              .onClick(() => { this.moreOpen = !this.moreOpen; this.plusOpen = false; })
          }.width('100%').height(56).padding({ left: 16, right: 16 })
        }

        if (!this.editMode) {
          SearchBar({ query: $query }).margin({ left: 24, right: 24, top: 8, bottom: 16 })
        }

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
                  editMode: this.editMode,
                  selected: this.multiSelected[a.id] === true,
                  onTap: () => {
                    if (this.editMode) this.toggleSelected(a.id);
                    else this.copy(a);
                  },
                  onLongPress: () => { if (!this.editMode) this.enterEditMode(a.id); },
                  onRefresh: () => this.refreshHotp(a)
                })
              }
              .swipeAction(this.editMode ? {} : {
                start: { builder: () => { this.SwipeStart(a) } },
                end: { builder: () => { this.SwipeEnd(a) } },
                edgeEffect: SwipeEdgeEffect.None
              })
            }, (a: OtpAccount) => `${a.id}-${this.listVersion}`)
          }
          .layoutWeight(1)
          .padding({ left: 24, right: 24, top: this.editMode ? 8 : 0, bottom: 16 })
          .onItemDragStart((_event: ItemDragInfo, itemIndex: number) => {
            if (!this.editMode) return;
            this.dragSource = itemIndex;
            return this.DragPreview.bind(this);
          })
          .onItemDrop((_event: ItemDragInfo, itemIndex: number, insertIndex: number, isSuccess: boolean) => {
            const from = this.dragSource;
            this.dragSource = -1;
            if (!isSuccess || !this.editMode) return;
            this.reorder(from >= 0 ? from : itemIndex, insertIndex);
          })
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

      if (!this.editMode) {
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
      }

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
