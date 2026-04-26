import { common } from '@kit.AbilityKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { defaultAccount, OtpAccount, OtpType } from '../model/OtpAccount';
import { OtpAccountStore } from '../services/OtpAccountStore';
import { SecretVault } from '../services/SecretVault';
import { decryptBackup, BackupFile } from '../utils/BackupCrypto';
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
struct ImportPage {
  @State filename: string = '';
  @State pickedUri: string = '';
  @State password: string = '';
  @State busy: boolean = false;

  private async pick(): Promise<void> {
    try {
      const docPicker = new picker.DocumentViewPicker();
      const opts: picker.DocumentSelectOptions = {
        maxSelectNumber: 1
      };
      const uris = await docPicker.select(opts);
      if (!uris || uris.length === 0) return;
      this.pickedUri = uris[0];
      const parts = this.pickedUri.split('/');
      this.filename = parts.length > 0 ? parts[parts.length - 1] : this.pickedUri;
    } catch (e) {
      console.error('[ImportPage.pick]', e);
    }
  }

  private async doImport(): Promise<void> {
    if (this.busy) return;
    if (!this.pickedUri) return;
    if (this.password.length < 6) {
      this.toast('密码至少 6 位');
      return;
    }
    try {
      this.busy = true;
      const f = fileIo.openSync(this.pickedUri, fileIo.OpenMode.READ_ONLY);
      let text = '';
      try {
        const stat = fileIo.statSync(f.fd);
        const size = stat.size;
        const buf = new ArrayBuffer(size);
        fileIo.readSync(f.fd, buf);
        text = util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(buf));
      } finally {
        fileIo.closeSync(f);
      }
      const file: BackupFile = JSON.parse(text) as BackupFile;
      const plainText = await decryptBackup(this.password, file);
      const plain: BackupPlain = JSON.parse(plainText) as BackupPlain;

      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      let order = await OtpAccountStore.maxOrderIndex(ctx);
      let count = 0;
      for (const a of plain.accounts) {
        try {
          const acct: OtpAccount = defaultAccount();
          acct.id = util.generateRandomUUID(false);
          acct.name = a.name || '';
          acct.note = a.note || '';
          acct.type = a.type === 'hotp' ? OtpType.HOTP : OtpType.TOTP;
          acct.period = a.period || 30;
          acct.digits = a.digits || 6;
          acct.algorithm = (a.algorithm === 'SHA256' || a.algorithm === 'SHA512')
            ? (a.algorithm as 'SHA256' | 'SHA512')
            : 'SHA1';
          acct.counter = a.counter || 0;
          acct.iconKey = a.iconKey || '';
          order += 1;
          acct.orderIndex = order;
          const now = Date.now();
          acct.createdAt = now;
          acct.updatedAt = now;
          await SecretVault.put(acct.id, a.secret);
          await OtpAccountStore.insert(ctx, acct);
          count += 1;
        } catch (e) {
          console.error('[ImportPage.insert]', e);
        }
      }
      this.toast(`已导入 ${count} 个账号`);
      this.getUIContext().getRouter().back();
    } catch (e) {
      console.error('[ImportPage.doImport]', e);
      this.toast('密码错误或文件已损坏');
    } finally {
      this.busy = false;
    }
  }

  private toast(msg: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: msg });
    } catch (e) {
      console.error('[ImportPage.toast]', e);
    }
  }

  @Builder NavButton(icon: Resource, onTap: () => void) {
    Stack() {
      Image(icon).width(24).height(24)
    }
    .width(40).height(40)
    .onClick(onTap)
  }

  @Builder PageBody() {
    Column() {
      Row() {
        this.NavButton($r('app.media.nav_back'), () => this.getUIContext().getRouter().back())
        Text($r('app.string.import_title'))
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

      Column() {
        Button($r('app.string.import_btn_pick'))
          .backgroundColor($r('app.color.bg_button'))
          .fontColor($r('app.color.accent_blue'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .height(48).width('100%').borderRadius(24)
          .onClick(() => this.pick())
        if (this.filename) {
          Text(this.filename)
            .fontSize(13).fontColor($r('app.color.text_secondary'))
            .margin({ top: 8 })
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%').textAlign(TextAlign.Center)
        }
      }
      .padding({ left: 24, right: 24 })
      .margin({ top: 32, bottom: 24 })
      .width('100%')

      Column() {
        TextInput({ placeholder: $r('app.string.import_password_hint'), text: this.password })
          .type(InputType.Password).fontSize(16).backgroundColor(Color.Transparent)
          .placeholderColor($r('app.color.text_placeholder'))
          .padding({ left: 0, right: 0 })
          .height(50)
          .onChange((v: string) => { this.password = v; })
      }
      .backgroundColor($r('app.color.bg_card'))
      .borderRadius(20)
      .padding({ left: 24, right: 24 })
      .margin({ left: 24, right: 24, bottom: 16 })

      Button($r('app.string.import_btn_decrypt'))
        .backgroundColor($r('app.color.accent_blue'))
        .fontColor(Color.White).fontSize(18).fontWeight(FontWeight.Medium)
        .height(48).width('80%').borderRadius(24)
        .margin({ bottom: 24 })
        .enabled(!this.busy && this.pickedUri.length > 0)
        .onClick(() => this.doImport())
    }.width('100%').height('100%')
  }

  build() {
    Stack() {
      PageContainer({ content: () => { this.PageBody() } })
    }.width('100%').height('100%')
  }
}
