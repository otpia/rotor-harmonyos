import { common } from '@kit.AbilityKit';
import { IconCache } from '../services/IconCache';
import {
  ICON_IMG,
  ICON_LIB,
  avatarColor,
  avatarInitial,
  iconByKey,
  issuerImage
} from '../utils/IssuerIcon';

@Extend(Image)
function brandIconStyle(diameter: number) {
  .width(diameter)
  .height(diameter)
  .objectFit(ImageFit.Contain)
  .interpolation(ImageInterpolation.High)
  .draggable(false)
}

// 服务图标：手动选的图标优先，其次按名称匹配内置品牌图标，都没有时显示首字母圆形头像；
// 品牌图标按原比例完整显示，深浅色版本由资源目录自动切换
@Component
export struct IssuerAvatar {
  @Prop name: string = '';
  @Prop @Watch('loadCustom') iconKey: string = '';
  @Prop diameter: number = 24;
  @State customUri: string = '';

  aboutToAppear(): void {
    this.loadCustom();
  }

  // 图库图标：本地文件存在时显示，其他设备上没有文件时回退到内置图标或首字母头像
  private loadCustom(): void {
    this.customUri = '';
    if (!this.iconKey.startsWith(ICON_IMG)) {
      return;
    }
    const host = this.getUIContext().getHostContext();
    if (host === undefined) {
      return;
    }
    const path = IconCache.cachedPath(host as common.Context, this.iconKey);
    if (path.length > 0) {
      this.customUri = IconCache.uriOf(path);
    }
  }

  private brandIcon(): Resource | undefined {
    if (this.iconKey.startsWith(ICON_LIB)) {
      const r = iconByKey(this.iconKey.substring(ICON_LIB.length));
      if (r !== undefined) {
        return r;
      }
    }
    return issuerImage(this.name);
  }

  private brandImage(): Resource {
    const r = this.brandIcon();
    return r !== undefined ? r : $r('app.media.appicon');
  }

  build() {
    if (this.customUri.length > 0) {
      Image(this.customUri)
        .brandIconStyle(this.diameter)
    } else if (this.brandIcon() !== undefined) {
      Image(this.brandImage())
        .brandIconStyle(this.diameter)
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
