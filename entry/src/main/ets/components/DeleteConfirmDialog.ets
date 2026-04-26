@CustomDialog
export struct DeleteConfirmDialog {
  controller: CustomDialogController;
  name: string = '';
  onConfirm?: () => void;

  build() {
    Column() {
      Text(`是否要删除 ${this.name}？`)
        .fontSize(20)
        .fontColor($r('app.color.text_primary'))
        .textAlign(TextAlign.Center)
        .width('100%')
        .padding({ left: 24, right: 24 })
        .margin({ top: 28, bottom: 20 })
      Row() {
        Text($r('app.string.btn_cancel'))
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.accent_blue'))
          .textAlign(TextAlign.Center)
          .height(48)
          .layoutWeight(1)
          .onClick(() => this.controller.close())
        Divider()
          .vertical(true)
          .color($r('app.color.divider'))
          .strokeWidth(0.5)
          .height(24)
        Text($r('app.string.btn_delete'))
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.accent_red'))
          .textAlign(TextAlign.Center)
          .height(48)
          .layoutWeight(1)
          .onClick(() => {
            this.controller.close();
            if (this.onConfirm) this.onConfirm();
          })
      }
      .alignItems(VerticalAlign.Center)
      .width('100%')
    }
    .backgroundColor($r('app.color.bg_dialog'))
    .borderRadius(20)
    .margin({ left: 8, right: 8, bottom: 8 })
    .width(344)
  }
}
