import { common } from '@kit.AbilityKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { OtpAccount } from '../model/OtpAccount';
import { OtpAccountStore } from '../services/OtpAccountStore';
import { SecretVault } from '../services/SecretVault';
import { encryptBackup, BackupFile } from '../utils/BackupCrypto';
import { PageContainer } from '../components/PageContainer';
import { PasswordDialog } from '../components/PasswordDialog';

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

@Entry
@Component
struct ExportPage {
  @State accounts: OtpAccount[] = [];
  @State selected: Record<string, boolean> = {};
  @State busy: boolean = false;

  passwordDialog: CustomDialogController = new CustomDialogController({
    builder: PasswordDialog({
      title: $r('app.string.export_password_hint'),
      needConfirm: true,
      onSubmit: (pwd: string) => this.runExport(pwd)
    }),
    alignment: DialogAlignment.Bottom,
    customStyle: true
  });

  aboutToAppear(): void {
    this.load();
  }

  private async load(): Promise<void> {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      this.accounts = await OtpAccountStore.listAll(ctx);
      const sel: Record<string, boolean> = {};
      for (const a of this.accounts) sel[a.id] = false;
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

  private openExport(): void {
    if (this.busy) return;
    if (this.selectedCount() === 0) {
      this.toast('请至少选择一个账号');
      return;
    }
    this.passwordDialog.open();
  }

  private async runExport(password: string): Promise<void> {
    if (this.busy) return;
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

      this.toast(`已导出 ${items.length} 个账号`);
      this.getUIContext().getRouter().back();
    } catch (e) {
      console.error('[ExportPage.runExport]', e);
      this.toast('导出失败');
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
      Image($r('app.media.nav_back')).width(24).height(24)
    }
    .width(40).height(40)
    .onClick(onTap)
  }

  @Builder ToolbarButton(icon: Resource, label: ResourceStr, onTap: () => void) {
    Column() {
      Image(icon).width(24).height(24)
      Text(label)
        .fontSize(10)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: 0 })
    }
    .width(80).height(62)
    .justifyContent(FlexAlign.Center)
    .onClick(onTap)
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
        Text($r('app.string.export_title'))
          .fontSize(20)
          .fontWeight(FontWeight.Bolder)
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
        this.ToolbarButton($r('app.media.toolbar_export'), $r('app.string.menu_export_short'), () => this.openExport())
        this.ToolbarButton($r('app.media.toolbar_select_all'), $r('app.string.menu_select_all_short'), () => this.toggleAll())
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
