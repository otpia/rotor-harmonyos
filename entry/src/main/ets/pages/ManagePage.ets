import { common } from '@kit.AbilityKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { ItemState, SymbolGlyphModifier, ToolBar, ToolBarOptions, uiMaterial } from '@kit.ArkUI';
import { HdsNavDestination, hdsMaterial, ScrollEffectType } from '@kit.UIDesignKit';
import { OtpAccount } from '../model/OtpAccount';
import { OtpAccountStore } from '../services/OtpAccountStore';
import { SecretVault } from '../services/SecretVault';
import { encryptBackup, BackupFile } from '../utils/BackupCrypto';
import { getString } from '../utils/I18n';
import { IssuerAvatar } from '../components/IssuerAvatar';
import { PasswordSheet } from '../components/PasswordSheet';

interface BackupAccount {
  name: string;
  note: string;
  type: string;
  period: number;
  digits: number;
  algorithm: string;
  counter: number;
  iconKey: string;
  secret: string;
}

interface BackupPlain {
  accounts: BackupAccount[];
}

// 多选编辑页：批量删除与加密导出
@Component
export struct ManagePage {
  @Consume('pathStack') pathStack: NavPathStack;
  @State accounts: OtpAccount[] = [];
  @State selected: Record<string, boolean> = {};
  @State busy: boolean = false;
  @State pwdSheetOpen: boolean = false;
  @StorageProp('bottomSafeAreaPx') bottomSafeAreaPx: number = 0;
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.load();
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
      console.error('[ManagePage.toast]', e);
    }
  }

  private async load(): Promise<void> {
    try {
      this.accounts = await OtpAccountStore.listAll(this.ctx());
      const sel: Record<string, boolean> = {};
      for (const a of this.accounts) {
        sel[a.id] = false;
      }
      this.selected = sel;
    } catch (e) {
      console.error('[ManagePage.load]', e);
    }
  }

  private selectedCount(): number {
    let n = 0;
    for (const a of this.accounts) {
      if (this.selected[a.id]) {
        n++;
      }
    }
    return n;
  }

  private selectedIds(): string[] {
    const ids: string[] = [];
    for (const a of this.accounts) {
      if (this.selected[a.id]) {
        ids.push(a.id);
      }
    }
    return ids;
  }

  private toggleAll(): void {
    const allOn = this.accounts.length > 0 && this.selectedCount() === this.accounts.length;
    const next: Record<string, boolean> = {};
    for (const a of this.accounts) {
      next[a.id] = !allOn;
    }
    this.selected = next;
  }

  private toggleOne(id: string, on: boolean): void {
    const next: Record<string, boolean> = {};
    for (const k of Object.keys(this.selected)) {
      next[k] = this.selected[k];
    }
    next[id] = on;
    this.selected = next;
  }

  private askDelete(): void {
    const ids = this.selectedIds();
    if (ids.length === 0) {
      return;
    }
    const ctx = this.ctx();
    let message = '';
    if (ids.length === 1) {
      let name = '';
      for (const a of this.accounts) {
        if (a.id === ids[0]) {
          name = a.name;
          break;
        }
      }
      message = getString(ctx, 'delete_confirm_message', name);
    } else {
      message = getString(ctx, 'delete_confirm_multi', ids.length);
    }
    try {
      this.getUIContext().showAlertDialog({
        message: message,
        systemMaterial: new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.ULTRA_THICK }),
        primaryButton: {
          value: $r('app.string.btn_cancel'),
          action: () => {
          }
        },
        secondaryButton: {
          value: $r('app.string.btn_delete'),
          fontColor: $r('sys.color.warning'),
          action: () => {
            this.runDelete(ids);
          }
        }
      });
    } catch (e) {
      console.error('[ManagePage.askDelete]', e);
    }
  }

  private async runDelete(ids: string[]): Promise<void> {
    if (this.busy) {
      return;
    }
    const ctx = this.ctx();
    try {
      this.busy = true;
      for (const id of ids) {
        try {
          await SecretVault.remove(id);
          await OtpAccountStore.delete(ctx, id);
        } catch (e) {
          console.error('[ManagePage.runDelete.item]', e);
        }
      }
      await this.load();
      this.toast(getString(ctx, 'toast_deleted_count', ids.length));
    } catch (e) {
      console.error('[ManagePage.runDelete]', e);
    } finally {
      this.busy = false;
    }
  }

  private openExport(): void {
    if (this.busy) {
      return;
    }
    if (this.selectedCount() === 0) {
      this.toast($r('app.string.toast_select_at_least_one'));
      return;
    }
    this.pwdSheetOpen = true;
  }

  private async runExport(password: string): Promise<void> {
    this.pwdSheetOpen = false;
    if (this.busy) {
      return;
    }
    const ctx = this.ctx();
    try {
      this.busy = true;
      const items: BackupAccount[] = [];
      for (const a of this.accounts) {
        if (!this.selected[a.id]) {
          continue;
        }
        const sec = await SecretVault.get(a.id);
        if (!sec) {
          continue;
        }
        items.push({
          name: a.name,
          note: a.note,
          type: a.type,
          period: a.period,
          digits: a.digits,
          algorithm: a.algorithm,
          counter: a.counter,
          iconKey: a.iconKey,
          secret: sec
        });
      }
      const plain: BackupPlain = { accounts: items };
      const file: BackupFile = await encryptBackup(password, JSON.stringify(plain));
      const json = JSON.stringify(file);

      const docPicker = new picker.DocumentViewPicker(ctx);
      const now = new Date();
      const pad = (n: number): string => n < 10 ? '0' + String(n) : String(n);
      const filename = `rotor-${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(now.getDate())}-${pad(now.getHours())}${pad(now.getMinutes())}.rotorbak`;
      const saveOpts: picker.DocumentSaveOptions = { newFileNames: [filename] };
      const uris = await docPicker.save(saveOpts);
      if (!uris || uris.length === 0) {
        return;
      }
      const enc = new util.TextEncoder('utf-8');
      const bytes = enc.encodeInto(json);
      const buf = new ArrayBuffer(bytes.length);
      new Uint8Array(buf).set(bytes);
      const f = fileIo.openSync(uris[0], fileIo.OpenMode.READ_WRITE);
      try {
        fileIo.writeSync(f.fd, buf);
      } finally {
        fileIo.closeSync(f);
      }
      this.toast(getString(ctx, 'toast_exported_count', items.length));
      this.pathStack.pop();
    } catch (e) {
      console.error('[ManagePage.runExport]', e);
      this.toast($r('app.string.toast_export_failed'));
    } finally {
      this.busy = false;
    }
  }

  // 底部工具栏；选中数为 0 时删除与导出置灰，列表随选中数变化重建以刷新状态
  private toolbarList(): ToolBarOptions {
    const disabled = this.selectedCount() === 0;
    const list = new ToolBarOptions();
    list.push({
      content: $r('app.string.btn_delete'),
      toolBarSymbolOptions: { normal: new SymbolGlyphModifier($r('sys.symbol.trash')) },
      state: disabled ? ItemState.DISABLE : ItemState.ENABLE,
      action: () => {
        this.askDelete();
      }
    });
    list.push({
      content: $r('app.string.menu_export_short'),
      toolBarSymbolOptions: { normal: new SymbolGlyphModifier($r('sys.symbol.share')) },
      state: disabled ? ItemState.DISABLE : ItemState.ENABLE,
      action: () => {
        this.openExport();
      }
    });
    list.push({
      content: $r('app.string.menu_select_all_short'),
      toolBarSymbolOptions: { normal: new SymbolGlyphModifier($r('sys.symbol.list_checkmark')) },
      action: () => {
        this.toggleAll();
      }
    });
    return list;
  }

  @Builder BottomToolbar() {
    Column() {
      if (this.selectedCount() > 0) {
        ToolBar({ toolBarList: this.toolbarList(), activateIndex: -1 })
      } else {
        ToolBar({ toolBarList: this.toolbarList(), activateIndex: -1 })
      }
    }
    .width('100%')
    .padding({ bottom: Math.max(this.getUIContext().px2vp(this.bottomSafeAreaPx), 16) })
  }

  @Builder PwdSheet() {
    PasswordSheet({
      needConfirm: true,
      placeholder: $r('app.string.export_password_hint'),
      submitLabel: $r('app.string.menu_export_short'),
      onSubmit: (pwd: string) => {
        this.runExport(pwd);
      }
    })
  }

  @Builder AccountRow(a: OtpAccount) {
    Row() {
      IssuerAvatar({ name: a.name, diameter: 40 })
      Column() {
        Text(a.name)
          .fontSize($r('sys.float.Body_L'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (a.note.length > 0) {
          Text(a.note)
            .fontSize($r('sys.float.Body_M'))
            .fontColor($r('sys.color.font_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 2 })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 12, right: 12 })

      Checkbox()
        .select(this.selected[a.id] === true)
        .shape(CheckBoxShape.CIRCLE)
        .onChange((on: boolean) => this.toggleOne(a.id, on))
    }
    .width('100%')
    .height(64)
    .padding({ left: 12, right: 12 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor($r('sys.color.comp_background_list_card'))
    .borderRadius($r('sys.float.corner_radius_level8'))
  }

  build() {
    HdsNavDestination() {
      Column() {
        List({ space: 12, scroller: this.scroller }) {
          ForEach(this.accounts, (a: OtpAccount) => {
            ListItem() {
              this.AccountRow(a)
            }
            .onClick(() => this.toggleOne(a.id, !this.selected[a.id]))
          }, (a: OtpAccount) => a.id)
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 16, right: 16 })
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .contentEndOffset(16)
        .clipContent(ContentClipMode.SAFE_AREA)
        .bindSheet($$this.pwdSheetOpen, this.PwdSheet(), {
          systemMaterial: new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.ULTRA_THICK }),
          detents: [SheetSize.FIT_CONTENT],
          title: { title: $r('app.string.export_password_hint') },
          showClose: true,
          preferType: SheetType.BOTTOM
        })

        this.BottomToolbar()
      }
      .width('100%')
      .height('100%')
    }
    .backgroundColor($r('sys.color.background_secondary'))
    .titleBar({
      content: {
        title: {
          mainTitle: $r('app.string.btn_edit'),
          subTitle: getString(this.ctx(), 'selected_count', this.selectedCount())
        }
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
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP])
  }
}
