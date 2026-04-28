import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { OtpAccount, OtpType, defaultAccount } from '../model/OtpAccount';
import { OtpAccountStore } from '../services/OtpAccountStore';
import { SecretVault } from '../services/SecretVault';
import { isValidBase32, base32Normalize } from '../utils/Base32';
import { TypeSheet } from '../components/TypeSheet';
import { PageContainer } from '../components/PageContainer';

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
    customStyle: true,
    maskColor: $r('app.color.scrim')
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
    try {
      if (!this.valid()) {
        const msg = !this.account.name
          ? $r('app.string.name_required')
          : $r('app.string.secret_invalid');
        try {
          this.getUIContext().getPromptAction().showToast({ message: msg });
        } catch (e) {
          console.error('[EditPage.save] showToast failed', e);
        }
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
    } catch (e) {
      console.error('[EditPage.save]', e);
    }
  }

  @Builder NavButton(symbol: Resource, onTap: () => void) {
    Stack() {
      SymbolGlyph(symbol)
        .fontSize(24)
        .fontColor([$r('app.color.text_primary')])
    }
    .width(40).height(40)
    .onClick(onTap)
  }

  @Builder Field(label: Resource, value: string, onChange: (v: string) => void) {
    Row() {
      Text(label).fontSize(18).fontColor($r('app.color.text_primary')).width(60)
      TextInput({ text: value })
        .fontSize(18)
        .fontColor($r('app.color.text_primary'))
        .placeholderColor($r('app.color.text_placeholder'))
        .backgroundColor(Color.Transparent)
        .caretStyle({ width: 2, color: $r('app.color.accent_blue') })
        .caretColor($r('app.color.accent_blue'))
        .padding(0)
        .layoutWeight(1)
        .height(50)
        .onChange(onChange)
    }
    .padding({ left: 24, right: 24 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder PageBody() {
    Column() {
      Row() {
        this.NavButton($r('sys.symbol.xmark'), () => this.getUIContext().getRouter().back())
        Text(this.isEdit ? $r('app.string.edit_title') : $r('app.string.add_title'))
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .margin({ left: 8 })
          .layoutWeight(1)
        this.NavButton($r('sys.symbol.checkmark'), () => this.save())
      }
      .height(56)
      .width('100%')
      .padding({ left: 16, right: 16 })
      .alignItems(VerticalAlign.Center)

      Column() {
        Image($r('app.media.edit_avatar')).width(80).height(80)
      }
      .margin({ top: 64, bottom: 64 })

      Column() {
        this.Field($r('app.string.label_name'), this.account.name, (v: string) => { this.account.name = v; })
        this.Field($r('app.string.label_note'), this.account.note, (v: string) => { this.account.note = v; })
      }
      .padding({ top: 4, bottom: 4 })
      .backgroundColor($r('app.color.bg_card'))
      .borderRadius(20)
      .margin({ left: 8, right: 8, bottom: 8 })

      Column() {
        this.Field($r('app.string.label_secret'), this.secret, (v: string) => { this.secret = v; })
      }
      .padding({ top: 4, bottom: 4 })
      .backgroundColor($r('app.color.bg_card'))
      .borderRadius(20)
      .margin({ left: 8, right: 8, bottom: 8 })

      Column() {
        Row() {
          Text($r('app.string.label_type')).fontSize(18).fontColor($r('app.color.text_primary')).width(60)
          Text(this.account.type === OtpType.TOTP ? $r('app.string.type_totp') : $r('app.string.type_hotp'))
            .fontSize(18)
            .fontColor($r('app.color.text_secondary'))
            .layoutWeight(1)
            .textAlign(TextAlign.End)
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(24)
            .fontColor([$r('app.color.text_secondary')])
            .margin({ left: 8 })
        }
        .height(50)
        .padding({ left: 24, right: 24 })
        .onClick(() => this.typeDialog.open())
      }
      .padding({ top: 4, bottom: 4 })
      .backgroundColor($r('app.color.bg_card'))
      .borderRadius(20)
      .margin({ left: 8, right: 8 })

      if (this.account.type === OtpType.HOTP) {
        Column() {
          this.Field($r('app.string.label_counter'), String(this.account.counter), (v: string) => {
            const n = parseInt(v);
            this.account.counter = isNaN(n) ? 0 : n;
          })
        }
        .padding({ top: 4, bottom: 4 })
        .backgroundColor($r('app.color.bg_card'))
        .borderRadius(20)
        .margin({ left: 8, right: 8, top: 8 })
      }
    }.width('100%').height('100%')
  }

  build() {
    Stack() {
      PageContainer({ content: () => { this.PageBody() } })
    }.width('100%').height('100%')
  }
}
