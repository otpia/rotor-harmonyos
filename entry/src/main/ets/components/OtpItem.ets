import { ProgressRing } from './ProgressRing';
import { OtpAccount, OtpType } from '../model/OtpAccount';
import { iconForName } from '../utils/IssuerIcon';
import { formatGroups } from '../services/OtpEngine';

@Component
export struct OtpItem {
  @Prop account: OtpAccount;
  @Prop code: string = '------';
  @Prop remaining: number = 30;
  onTap?: () => void;
  onRefresh?: () => void;

  private codeColor(): Resource {
    return this.remaining < 6 ? $r('app.color.accent_red') : $r('app.color.text_primary');
  }

  @Styles cardNormal() {
    .backgroundColor($r('app.color.bg_card'))
  }

  @Styles cardPressed() {
    .backgroundColor($r('app.color.bg_card_active'))
  }

  build() {
    Column() {
      Row() {
        Image(iconForName(this.account.name)).width(24).height(24).borderRadius(12)
        Text(this.account.name)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .margin({ left: 8 })
          .fontColor($r('app.color.text_primary'))
      }
      .alignItems(VerticalAlign.Center)
      .width('100%')

      Row() {
        Text(formatGroups(this.code))
          .fontSize(40)
          .fontWeight(FontWeight.Bolder)
          .fontColor(this.codeColor())
          .layoutWeight(1)
        if (this.account.type === OtpType.HOTP) {
          Text($r('app.string.btn_refresh'))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.accent_blue'))
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(14)
            .backgroundColor($r('app.color.bg_button'))
            .onClick(() => { if (this.onRefresh) this.onRefresh(); })
        } else {
          ProgressRing({ period: this.account.period })
        }
      }
      .alignItems(VerticalAlign.Center)
      .margin({ top: 8 })
      .width('100%')

      Text(this.account.note)
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: 8 })
        .width('100%')
    }
    .padding({ left: 24, right: 24, top: 16, bottom: 16 })
    .borderRadius(20)
    .width('100%')
    .stateStyles({ normal: this.cardNormal, pressed: this.cardPressed })
    .onClick(() => { if (this.onTap) this.onTap(); })
  }
}
