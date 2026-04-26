import { bundleManager, common } from '@kit.AbilityKit';
import { PageContainer } from '../components/PageContainer';

@Entry
@Component
struct AboutPage {
  @State versionName: string = '';

  aboutToAppear(): void {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const flags = bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT;
      bundleManager.getBundleInfoForSelf(flags).then((info: bundleManager.BundleInfo) => {
        this.versionName = info.versionName || '';
      }).catch((e: Error) => {
        console.error('[AboutPage.versionName]', e);
      });
      // ctx 仅作为引用避免被裁剪；后续可能用到
      void ctx;
    } catch (e) {
      console.error('[AboutPage.aboutToAppear]', e);
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

  @Builder PageBody() {
    Column() {
      Row() {
        this.NavButton($r('app.media.nav_close'), () => this.getUIContext().getRouter().back())
        Text($r('app.string.about_title'))
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

      Column() {
        Image($r('app.media.foreground'))
          .width(96).height(96)
          .borderRadius(20)
          .backgroundColor('#0A59F7')
        Text($r('app.string.EntryAbility_label'))
          .fontSize(24)
          .fontWeight(FontWeight.Bolder)
          .fontColor($r('app.color.text_primary'))
          .margin({ top: 16 })
        Text(this.versionName ? `v${this.versionName}` : '')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Center)
      .margin({ top: 32, bottom: 24 })
      .width('100%')

      Column() {
        Text($r('app.string.about_description'))
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .lineHeight(22)
          .padding({ left: 24, right: 24, top: 16, bottom: 16 })
      }
      .backgroundColor($r('app.color.bg_card'))
      .borderRadius(20)
      .margin({ left: 24, right: 24 })
      .width('auto')
    }.width('100%').height('100%')
  }

  build() {
    Stack() {
      PageContainer({ content: () => { this.PageBody() } })
    }.width('100%').height('100%')
  }
}
