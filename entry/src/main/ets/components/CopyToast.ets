@Component
export struct CopyToast {
  @Prop visible: boolean = false;

  build() {
    if (this.visible) {
      Row() {
        Text($r('app.string.toast_copied'))
          .fontColor($r('app.color.text_primary'))
          .fontSize(14)
      }
      .padding({ left: 24, right: 24, top: 10, bottom: 10 })
      .backgroundColor($r('app.color.bg_card'))
      .borderRadius(20)
      .shadow({ radius: 8, color: '#1A000000', offsetY: 2 })
    }
  }
}
