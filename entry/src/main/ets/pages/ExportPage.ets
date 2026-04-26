import { common } from '@kit.AbilityKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { OtpAccount } from '../model/OtpAccount';
import { OtpAccountStore } from '../services/OtpAccountStore';
import { SecretVault } from '../services/SecretVault';
import { encryptBackup, BackupFile } from '../utils/BackupCrypto';
import { PageContainer } from '../components/PageContainer';

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
  @State password: string = '';
  @State password2: string = '';
  @State busy: boolean = false;

  aboutToAppear(): void {
    this.load();
  }

  private async load(): Promise<void> {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      this.accounts = await OtpAccountStore.listAll(ctx);
      const sel: Record<string, boolean> = {};
      for (const a of this.accounts) sel[a.id] = true;
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

  private async doExport(): Promise<void> {
    if (this.busy) return;
    if (this.password.length < 6) {
      this.toast('密码至少 6 位');
      return;
    }
    if (this.password !== this.password2) {
      this.toast('两次密码不一致');
      return;
    }
    if (this.selectedCount() === 0) return;
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
      const file: BackupFile = await encryptBackup(this.password, JSON.stringify(plain));
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
      console.error('[ExportPage.doExport]', e);
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

  @Builder NavButton(icon: Resource, onTap: () => void) {
    Stack() {
      Image(icon).width(24).height(24)
    }
    .width(40).height(40)
    .borderRadius(20)
    .backgroundColor($r('app.color.bg_button'))
    .onClick(onTap)
  }

  @Builder AccountRow(a: OtpAccount) {
    Row() {
      Column() {
        Text(a.name).fontSize(16).fontColor($r('app.color.text_primary')).fontWeight(FontWeight.Medium)
        if (a.note) {
          Text(a.note).fontSize(13).fontColor($r('app.color.text_secondary')).margin({ top: 2 })
        }
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      Toggle({ type: ToggleType.Checkbox, isOn: this.selected[a.id] === true })
        .selectedColor($r('app.color.accent_blue'))
        .onChange((on: boolean) => this.toggleOne(a.id, on))
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder PageBody() {
    Column() {
      Row() {
        this.NavButton($r('app.media.nav_close'), () => this.getUIContext().getRouter().back())
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

      Row() {
        Text($r('app.string.export_select_hint'))
          .fontSize(14).fontColor($r('app.color.text_secondary'))
          .layoutWeight(1)
        Text($r('app.string.select_all')).fontSize(14).fontColor($r('app.color.accent_blue'))
          .padding({ left: 8, right: 8 })
          .onClick(() => this.setAll(true))
        Text($r('app.string.select_none')).fontSize(14).fontColor($r('app.color.accent_blue'))
          .padding({ left: 8, right: 8 })
          .onClick(() => this.setAll(false))
      }.padding({ left: 24, right: 16, top: 8, bottom: 8 }).width('100%')

      Scroll() {
        Column() {
          ForEach(this.accounts, (a: OtpAccount) => {
            this.AccountRow(a)
          }, (a: OtpAccount) => a.id)
        }
        .backgroundColor($r('app.color.bg_card'))
        .borderRadius(20)
        .margin({ left: 24, right: 24, bottom: 16 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)

      Column() {
        TextInput({ placeholder: $r('app.string.export_password_hint'), text: this.password })
          .type(InputType.Password).fontSize(16).backgroundColor(Color.Transparent)
          .placeholderColor($r('app.color.text_placeholder'))
          .padding({ left: 0, right: 0 })
          .height(50)
          .onChange((v: string) => { this.password = v; })
        Divider().color($r('app.color.divider'))
        TextInput({ placeholder: $r('app.string.export_password_confirm'), text: this.password2 })
          .type(InputType.Password).fontSize(16).backgroundColor(Color.Transparent)
          .placeholderColor($r('app.color.text_placeholder'))
          .padding({ left: 0, right: 0 })
          .height(50)
          .onChange((v: string) => { this.password2 = v; })
      }
      .backgroundColor($r('app.color.bg_card'))
      .borderRadius(20)
      .padding({ left: 24, right: 24 })
      .margin({ left: 24, right: 24, bottom: 16 })

      Button($r('app.string.export_btn_save'))
        .backgroundColor($r('app.color.accent_blue'))
        .fontColor(Color.White).fontSize(18).fontWeight(FontWeight.Medium)
        .height(48).width('80%').borderRadius(24)
        .margin({ bottom: 24 })
        .enabled(!this.busy && this.selectedCount() > 0)
        .onClick(() => this.doExport())
    }.width('100%').height('100%')
  }

  build() {
    Stack() {
      PageContainer({ content: () => { this.PageBody() } })
    }.width('100%').height('100%')
  }
}
