@Component
export struct PageContainer {
  @StorageProp('topSafeAreaPx') topSafeAreaPx: number = 0;
  @StorageProp('bottomSafeAreaPx') bottomSafeAreaPx: number = 0;
  @BuilderParam content: () => void;

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.bg_app'))
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      Column() {
        this.content()
      }
      .width('100%')
      .height('100%')
      .padding({
        top: this.getUIContext().px2vp(this.topSafeAreaPx),
        bottom: this.getUIContext().px2vp(this.bottomSafeAreaPx)
      })
    }
    .width('100%')
    .height('100%')
  }
}
