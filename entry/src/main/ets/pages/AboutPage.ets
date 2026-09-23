import { bundleManager } from '@kit.AbilityKit';
import { HdsNavDestination, hdsMaterial, ScrollEffectType } from '@kit.UIDesignKit';

@Component
export struct AboutPage {
  @State versionName: string = '';
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    try {
      const flags = bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT;
      bundleManager.getBundleInfoForSelf(flags).then((info: bundleManager.BundleInfo) => {
        this.versionName = info.versionName || '';
      }).catch((e: Error) => {
        console.error('[AboutPage.versionName]', e);
      });
    } catch (e) {
      console.error('[AboutPage.aboutToAppear]', e);
    }
  }

  build() {
    HdsNavDestination() {
      Scroll(this.scroller) {
        Column() {
          Image($r('app.media.appicon'))
            .width(96)
            .height(96)
            .margin({ top: 24 })
          Text($r('app.string.EntryAbility_label'))
            .fontSize($r('sys.float.Title_S'))
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary'))
            .margin({ top: 16 })
          Text(this.versionName.length > 0 ? `v${this.versionName}` : '')
            .fontSize($r('sys.float.Body_M'))
            .fontColor($r('sys.color.font_secondary'))
            .margin({ top: 4 })

          Text($r('app.string.about_description'))
            .fontSize($r('sys.float.Body_M'))
            .fontColor($r('sys.color.font_secondary'))
            .lineHeight(22)
            .padding(16)
            .width('100%')
            .backgroundColor($r('sys.color.comp_background_list_card'))
            .borderRadius($r('sys.float.corner_radius_level8'))
            .margin({ top: 32 })
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 24 })
      }
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .width('100%')
      .height('100%')
    }
    .backgroundColor($r('sys.color.background_secondary'))
    .titleBar({
      content: {
        title: { mainTitle: $r('app.string.about_title') }
      },
      style: {
        scrollEffectOpts: {
          enableScrollEffect: true,
          scrollEffectType: ScrollEffectType.GRADIENT_BLUR
        },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        }
      },
      avoidLayoutSafeArea: true,
      enableComponentSafeArea: true
    })
    .bindToScrollable([this.scroller])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
  }
}
