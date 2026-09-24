import { ProgressRing } from './ProgressRing';
import { IssuerAvatar } from './IssuerAvatar';
import { OtpAccount, OtpType } from '../model/OtpAccount';
import { formatGroups } from '../services/OtpEngine';

// 首页验证码卡片：图标、名称、大号验证码、倒计时环或刷新按钮、备注
@Component
export struct OtpCard {
  @Prop account: OtpAccount;
  @Prop code: string = '------';
  @Prop remaining: number = 30;
  onRefresh?: () => void;

  private codeColor(): Resource {
    if (this.account.type === OtpType.TOTP && this.remaining < 6) {
      return $r('sys.color.warning');
    }
    return $r('sys.color.font_primary');
  }

  @Styles cardNormal() {
    .backgroundColor(Color.Transparent)
  }

  @Styles cardPressed() {
    .backgroundColor($r('sys.color.interactive_pressed'))
  }

  // 外层铺不透明卡片底色，内层叠加半透明按压色，拖拽浮起压住相邻卡片时不透底
  build() {
    Column() {
      Column() {
        Row() {
          IssuerAvatar({ name: this.account.name, diameter: 24 })
          Text(this.account.name)
            .fontSize($r('sys.float.Body_L'))
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ left: 8 })
            .layoutWeight(1)
        }
        .alignItems(VerticalAlign.Center)
        .width('100%')

        Row() {
          Text(formatGroups(this.code))
            .fontSize(40)
            .fontWeight(FontWeight.Bold)
            .fontFamily('HarmonyOS Sans Condensed')
            .fontColor(this.codeColor())
            .layoutWeight(1)
          if (this.account.type === OtpType.HOTP) {
            Button($r('app.string.btn_refresh'))
              .buttonStyle(ButtonStyleMode.NORMAL)
              .controlSize(ControlSize.SMALL)
              .onClick(() => {
                if (this.onRefresh) {
                  this.onRefresh();
                }
              })
          } else {
            ProgressRing({ period: this.account.period })
          }
        }
        .alignItems(VerticalAlign.Center)
        .margin({ top: 8 })
        .width('100%')

        if (this.account.note.length > 0) {
          Text(this.account.note)
            .fontSize($r('sys.float.Body_M'))
            .fontColor($r('sys.color.font_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 8 })
            .width('100%')
        }
      }
      .padding(16)
      .borderRadius($r('sys.float.corner_radius_level8'))
      .width('100%')
      .stateStyles({ normal: this.cardNormal, pressed: this.cardPressed })
    }
    .borderRadius($r('sys.float.corner_radius_level8'))
    .width('100%')
    .backgroundColor($r('sys.color.comp_background_list_card'))
  }
}
