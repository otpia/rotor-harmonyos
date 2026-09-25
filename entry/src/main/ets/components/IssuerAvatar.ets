import { issuerImage, avatarInitial, avatarColor } from '../utils/IssuerIcon';

// 服务图标：命中内置品牌图标时按原比例完整显示，深浅色版本由资源目录自动切换；否则显示首字母圆形头像
@Component
export struct IssuerAvatar {
  @Prop name: string = '';
  @Prop diameter: number = 24;

  private hasImage(): boolean {
    return issuerImage(this.name) !== undefined;
  }

  private image(): Resource {
    const r = issuerImage(this.name);
    return r !== undefined ? r : $r('app.media.appicon');
  }

  build() {
    if (this.hasImage()) {
      Image(this.image())
        .width(this.diameter)
        .height(this.diameter)
        .objectFit(ImageFit.Contain)
        .interpolation(ImageInterpolation.High)
        .draggable(false)
    } else {
      Text(avatarInitial(this.name))
        .fontSize(this.diameter * 0.45)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_on_primary'))
        .textAlign(TextAlign.Center)
        .width(this.diameter)
        .height(this.diameter)
        .borderRadius(this.diameter / 2)
        .backgroundColor(avatarColor(this.name))
    }
  }
}
