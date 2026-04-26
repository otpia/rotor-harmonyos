import { OtpType } from '../model/OtpAccount';

@CustomDialog
export struct TypeSheet {
  controller: CustomDialogController;
  selected: OtpType = OtpType.TOTP;
  onSelect?: (t: OtpType) => void;

  @Builder TypeRow(label: Resource, t: OtpType, disabled: boolean) {
    Row() {
      Text(label).fontSize(18)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
      Radio({ value: String(t), group: 'otp_type' })
        .width(20).height(20)
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
    .height(50)
    .padding({ left: 24, right: 24 })
    .opacity(disabled ? 0.5 : 1)
  }

  build() {
    Column() {
      Text($r('app.string.label_type'))
        .fontSize(24).fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .alignSelf(ItemAlign.Start)
        .padding({ top: 16, left: 24, bottom: 8 })
      this.TypeRow($r('app.string.type_hotp'), OtpType.HOTP, false)
      this.TypeRow($r('app.string.type_totp'), OtpType.TOTP, false)
      Button($r('app.string.btn_cancel'))
        .backgroundColor($r('app.color.bg_button'))
        .fontColor($r('app.color.accent_blue'))
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .height(48)
        .borderRadius(24)
        .margin({ top: 16, left: 24, right: 24, bottom: 16 })
    }
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(20)
    .margin({ left: 8, right: 8, bottom: 8 })
    .width(344)
  }
}
