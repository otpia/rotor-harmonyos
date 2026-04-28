import { common } from '@kit.AbilityKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { OtpAccount } from '../model/OtpAccount';
import { OtpAccountStore } from '../services/OtpAccountStore';
import { SecretVault } from '../services/SecretVault';
import { encryptBackup, BackupFile } from '../utils/BackupCrypto';
import { getString } from '../utils/I18n';
import { PageContainer } from '../components/PageContainer';
import { PasswordDialog } from '../components/PasswordDialog';
import { DeleteConfirmDialog } from '../components/DeleteConfirmDialog';

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

interface ExportParams {
  prefilledIds?: string[];
}

@Entry
@Component
struct ExportPage {
  @State accounts: OtpAccount[] = [];
  @State selected: Record<string, boolean> = {};
  @State busy: boolean = false;
  @State pendingDeleteName: string = '';
  private prefilledIds: string[] = [];

  passwordDialog: CustomDialogController = new CustomDialogController({
    builder: PasswordDialog({
      title: $r('app.string.export_password_hint'),
      needConfirm: true,
      onSubmit: (pwd: string) => this.runExport(pwd)
    }),
    alignment: DialogAlignment.Bottom,
    customStyle: true,
    maskColor: $r('app.color.scrim')
  });

  deleteDialog: CustomDialogController = new CustomDialogController({
    builder: DeleteConfirmDialog({
      name: this.pendingDeleteName,
      onConfirm: () => this.runDelete()
    }),
    alignment: DialogAlignment.Bottom,
    customStyle: true,
    maskColor: $r('app.color.scrim')
  });

  aboutToAppear(): void {
    try {
      const params = this.getUIContext().getRouter().getParams() as ExportParams;
      if (params && params.prefilledIds && params.prefilledIds.length > 0) {
        this.prefilledIds = params.prefilledIds;
      }
    } catch (e) {
      console.error('[ExportPage.aboutToAppear]', e);
    }
    this.load();
  }

  private async load(): Promise<void> {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      this.accounts = await OtpAccountStore.listAll(ctx);
      const presetMap: Record<string, boolean> = {};
      for (const id of this.prefilledIds) presetMap[id] = true;
      const sel: Record<string, boolean> = {};
      for (const a of this.accounts) sel[a.id] = presetMap[a.id] === true;
      this.selected = sel;
    } catch (e) {
      console.error('[ExportPage.load]', e);
    }
  }

  private setAll(value: boolean): void {
    const next: Record<string, boolean> = {};
    for (const a of this.accounts) next[a.id] = value;
    this.selected = next;
  }

  private toggleAll(): void {
    const allOn = this.accounts.length > 0 && this.selectedCount() === this.accounts.length;
    this.setAll(!allOn);
  }

  private selectedCount(): number {
    let n = 0;
    for (const a of this.accounts) if (this.selected[a.id]) n++;
    return n;
  }

  private toggleOne(id: string, on: boolean): void {
    const next: Record<string, boolean> = {};
    for (const k of Object.keys(this.selected)) next[k] = this.selected[k];
    next[id] = on;
    this.selected = next;
  }

  private askDelete(): void {
    const n = this.selectedCount();
    if (n === 0) return;
    let name = '';
    if (n === 1) {
      for (const a of this.accounts) if (this.selected[a.id]) { name = a.name; break; }
    } else {
      name = `这 ${n} 项`;
    }
    this.pendingDeleteName = name;
    this.deleteDialog = new CustomDialogController({
      builder: DeleteConfirmDialog({
        name,
        onConfirm: () => this.runDelete()
      }),
      alignment: DialogAlignment.Bottom,
      customStyle: true,
      maskColor: $r('app.color.scrim')
    });
    this.deleteDialog.open();
  }

  private async runDelete(): Promise<void> {
    if (this.busy) return;
    try {
      this.busy = true;
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const ids: string[] = [];
      for (const a of this.accounts) if (this.selected[a.id]) ids.push(a.id);
      for (const id of ids) {
        try {
          await SecretVault.remove(id);
          await OtpAccountStore.delete(ctx, id);
        } catch (e) {
          console.error('[ExportPage.runDelete.item]', e);
        }
      }
      await this.load();
      this.toast(getString(ctx, 'toast_deleted_count', ids.length));
    } catch (e) {
      console.error('[ExportPage.runDelete]', e);
    } finally {
      this.busy = false;
    }
  }

  private openExport(): void {
    if (this.busy) return;
    if (this.selectedCount() === 0) {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      this.toast(getString(ctx, 'toast_select_at_least_one'));
      return;
    }
    this.passwordDialog.open();
  }

  private async runExport(password: string): Promise<void> {
    if (this.busy) return;
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    try {
      this.busy = true;
      const items: BackupAccount[] = [];
      for (const a of this.accounts) {
        if (!this.selected[a.id]) continue;
        const sec = await SecretVault.get(a.id);
        if (!sec) continue;
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

      const docPicker = new picker.DocumentViewPicker();
      const now = new Date();
      const pad = (n: number): string => n < 10 ? '0' + String(n) : String(n);
      const filename = `rotor-${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(now.getDate())}-${pad(now.getHours())}${pad(now.getMinutes())}.rotorbak`;
      const saveOpts: picker.DocumentSaveOptions = { newFileNames: [filename] };
      const uris = await docPicker.save(saveOpts);
      if (!uris || uris.length === 0) {
        this.busy = false;
        return;
      }
      const uri = uris[0];

      const enc = new util.TextEncoder('utf-8');
      const bytes = enc.encodeInto(json);
      const buf = new ArrayBuffer(bytes.length);
      new Uint8Array(buf).set(bytes);
      const f = fileIo.openSync(uri, fileIo.OpenMode.READ_WRITE);
      try {
        fileIo.writeSync(f.fd, buf);
      } finally {
        fileIo.closeSync(f);
      }

      this.toast(getString(ctx, 'toast_exported_count', items.length));
      this.getUIContext().getRouter().back();
    } catch (e) {
      console.error('[ExportPage.runExport]', e);
      this.toast(getString(ctx, 'toast_export_failed'));
    } finally {
      this.busy = false;
    }
  }

  private toast(msg: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: msg });
    } catch (e) {
      console.error('[ExportPage.toast]', e);
    }
  }

  @Builder NavBack(onTap: () => void) {
    Stack() {
      SymbolGlyph($r('sys.symbol.arrow_left'))
        .fontSize(24)
        .fontColor([$r('app.color.text_primary')])
    }
    .width(40).height(40)
    .onClick(onTap)
  }

  @Builder ToolbarButton(symbol: Resource, label: ResourceStr, onTap: () => void) {
    Column() {
      SymbolGlyph(symbol)
        .fontSize(24)
        .fontColor([$r('app.color.text_primary')])
      Text(label)
        .fontSize(10)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: 6 })
    }
    .width(80).height(72)
    .justifyContent(FlexAlign.Center)
    .onClick(onTap)
  }

  @Builder ToolbarDeleteButton() {
    Column() {
      SymbolGlyph($r('sys.symbol.trash'))
        .fontSize(24)
        .fontColor([$r('app.color.accent_red')])
        .opacity(this.selectedCount() > 0 ? 1 : 0.4)
      Text($r('app.string.btn_delete'))
        .fontSize(10)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.accent_red'))
        .opacity(this.selectedCount() > 0 ? 1 : 0.4)
        .margin({ top: 6 })
    }
    .width(80).height(72)
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      if (this.selectedCount() > 0) this.askDelete();
    })
  }

  @Builder AccountRow(a: OtpAccount) {
    Row() {
      Column() {
        Text(a.name)
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        if (a.note) {
          Text(a.note)
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 2 })
        }
      }
      .alignItems(HorizontalAlign.Start).layoutWeight(1)

      Checkbox()
        .select(this.selected[a.id] === true)
        .selectedColor($r('app.color.accent_blue'))
        .shape(CheckBoxShape.ROUNDED_SQUARE)
        .width(20).height(20)
        .onChange((on: boolean) => this.toggleOne(a.id, on))
    }
    .width('100%')
    .height(78)
    .padding({ left: 24, right: 24 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(20)
    .onClick(() => this.toggleOne(a.id, !this.selected[a.id]))
  }

  @Builder PageBody() {
    Column() {
      Row() {
        this.NavBack(() => this.getUIContext().getRouter().back())
        Text($r('app.string.btn_edit'))
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .margin({ left: 8 })
          .layoutWeight(1)
      }
      .height(56)
      .width('100%')
      .padding({ left: 16, right: 16 })
      .alignItems(VerticalAlign.Center)

      Text(`已选择 ${this.selectedCount()} 项`)
        .fontSize(32)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .padding({ left: 24, right: 24, top: 8, bottom: 16 })

      Scroll() {
        Column({ space: 8 }) {
          ForEach(this.accounts, (a: OtpAccount) => {
            this.AccountRow(a)
          }, (a: OtpAccount) => a.id)
        }
        .padding({ left: 24, right: 24, bottom: 16 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)

      Row() {
        this.ToolbarDeleteButton()
        this.ToolbarButton($r('sys.symbol.share'), $r('app.string.menu_export_short'), () => this.openExport())
        this.ToolbarButton($r('sys.symbol.list_checkmark'), $r('app.string.menu_select_all_short'), () => this.toggleAll())
      }
      .width('100%')
      .height(62)
      .justifyContent(FlexAlign.Center)
      .backgroundColor($r('app.color.bg_app'))
    }.width('100%').height('100%')
  }

  build() {
    Stack() {
      PageContainer({ content: () => { this.PageBody() } })
    }.width('100%').height('100%')
  }
}
