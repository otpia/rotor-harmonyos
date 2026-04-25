import { OtpType } from '../model/OtpAccount';

@CustomDialog
export struct TypeSheet {
  controller: CustomDialogController;
  selected: OtpType = OtpType.TOTP;
  onSelect?: (t: OtpType) => void;

  @Builder TypeRow(label: Resource, t: OtpType, disabled: boolean) {
    Row() {
      Text(label).fontSize(16)
        .fontColor(disabled ? $r('app.color.text_secondary') : $r('app.color.text_primary'))
        .layoutWeight(1)
      Radio({ value: String(t), group: 'otp_type' })
        .checked(this.selected === t)
        .enabled(!disabled)
        .onChange((on: boolean) => {
          if (on && !disabled) {
            this.selected = t;
            if (this.onSelect) this.onSelect(t);
            this.controller.close();
          }
        })
    }
    .padding({ top: 12, bottom: 12, left: 16, right: 16 })
    .opacity(disabled ? 0.5 : 1)
  }

  build() {
    Column() {
      Text($r('app.string.label_type')).fontSize(18).fontWeight(FontWeight.Bold)
        .alignSelf(ItemAlign.Start)
        .padding({ top: 16, left: 16, bottom: 8 })
      this.TypeRow($r('app.string.type_hotp'), OtpType.HOTP, true)
      this.TypeRow($r('app.string.type_totp'), OtpType.TOTP, false)
      Button($r('app.string.btn_cancel'))
        .backgroundColor(Color.Transparent)
        .fontColor($r('app.color.accent_blue'))
        .width('100%').height(48)
        .onClick(() => this.controller.close())
    }
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius({ topLeft: 16, topRight: 16 })
    .width('100%')
  }
}
