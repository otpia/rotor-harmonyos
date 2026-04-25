import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { OtpAccount, OtpType, defaultAccount } from '../model/OtpAccount';
import { OtpAccountStore } from '../services/OtpAccountStore';
import { SecretVault } from '../services/SecretVault';
import { isValidBase32, base32Normalize } from '../utils/Base32';
import { TypeSheet } from '../components/TypeSheet';

interface EditParams {
  id?: string;
  prefilled?: OtpAccount;
  prefilledSecret?: string;
}

@Entry
@Component
struct EditPage {
  @State account: OtpAccount = defaultAccount();
  @State secret: string = '';
  @State isEdit: boolean = false;

  typeDialog: CustomDialogController = new CustomDialogController({
    builder: TypeSheet({
      selected: this.account.type,
      onSelect: (t: OtpType) => { this.account.type = t; }
    }),
    alignment: DialogAlignment.Bottom,
    customStyle: true
  });

  aboutToAppear(): void {
    const params = this.getUIContext().getRouter().getParams() as EditParams;
    if (params && params.id) {
      this.isEdit = true;
      if (params.prefilled) {
        this.account = params.prefilled;
      }
      SecretVault.get(params.id).then((s: string) => { this.secret = s; }).catch(() => { this.secret = ''; });
    } else if (params && params.prefilled) {
      this.account = params.prefilled;
      this.secret = params.prefilledSecret || '';
    }
  }

  private valid(): boolean {
    if (!this.account.name || this.account.name.length === 0) return false;
    if (!isValidBase32(this.secret)) return false;
    return true;
  }

  private async save(): Promise<void> {
    if (!this.valid()) {
      const msg = !this.account.name ? '请填写名称' : '秘钥格式不正确';
      this.getUIContext().getPromptAction().showToast({ message: msg });
      return;
    }
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const now = Date.now();
    if (!this.isEdit) {
      this.account.id = util.generateRandomUUID(false);
      this.account.createdAt = now;
      this.account.orderIndex = (await OtpAccountStore.maxOrderIndex(ctx)) + 1;
    }
    this.account.updatedAt = now;
    await SecretVault.put(this.account.id, base32Normalize(this.secret));
    if (this.isEdit) {
      await OtpAccountStore.update(ctx, this.account);
    } else {
      await OtpAccountStore.insert(ctx, this.account);
    }
    this.getUIContext().getRouter().back();
  }

  @Builder Field(label: Resource, value: string, onChange: (v: string) => void) {
    Row() {
      Text(label).fontSize(14).fontColor($r('app.color.text_secondary')).width(56)
      TextInput({ text: value })
        .fontColor($r('app.color.text_primary'))
        .placeholderColor($r('app.color.text_placeholder'))
        .backgroundColor(Color.Transparent)
        .layoutWeight(1)
        .onChange(onChange)
    }
    .padding({ top: 12, bottom: 12, left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
  }

  build() {
    Column() {
      Row() {
        Text('×').fontSize(24).fontColor($r('app.color.text_primary'))
          .onClick(() => this.getUIContext().getRouter().back())
        Text(this.isEdit ? $r('app.string.edit_title') : $r('app.string.add_title'))
          .fontSize(18).margin({ left: 12 }).layoutWeight(1)
          .fontColor($r('app.color.text_primary'))
        Text('✓').fontSize(22)
          .fontColor(this.valid() ? $r('app.color.accent_blue') : $r('app.color.text_placeholder'))
          .onClick(() => this.save())
      }.padding(16).width('100%')

      Column() {
        Image($r('app.media.icon_default')).width(64).height(64).borderRadius(32).margin({ top: 24, bottom: 24 })
      }

      Column() {
        this.Field($r('app.string.label_name'), this.account.name, (v: string) => { this.account.name = v; })
        Divider().color($r('app.color.divider'))
        this.Field($r('app.string.label_note'), this.account.note, (v: string) => { this.account.note = v; })
      }
      .backgroundColor($r('app.color.bg_card'))
      .borderRadius(16)
      .margin({ left: 16, right: 16, bottom: 12 })

      Column() {
        this.Field($r('app.string.label_secret'), this.secret, (v: string) => { this.secret = v; })
      }
      .backgroundColor($r('app.color.bg_card'))
      .borderRadius(16)
      .margin({ left: 16, right: 16, bottom: 12 })

      Column() {
        Row() {
          Text($r('app.string.label_type')).fontSize(14).fontColor($r('app.color.text_secondary')).width(56)
          Text(this.account.type === OtpType.TOTP ? $r('app.string.type_totp') : $r('app.string.type_hotp'))
            .fontColor($r('app.color.text_placeholder')).layoutWeight(1).textAlign(TextAlign.End)
          Text('›').fontColor($r('app.color.text_placeholder')).margin({ left: 8 })
        }
        .padding({ top: 12, bottom: 12, left: 16, right: 16 })
        .onClick(() => this.typeDialog.open())
      }
      .backgroundColor($r('app.color.bg_card'))
      .borderRadius(16)
      .margin({ left: 16, right: 16 })
    }
    .width('100%').height('100%')
    .backgroundColor($r('app.color.bg_app'))
  }
}
