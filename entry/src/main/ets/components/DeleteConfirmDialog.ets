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
        .margin({ top: 24 })
      Row({ space: 8 }) {
        Button($r('app.string.btn_cancel'))
          .backgroundColor($r('app.color.bg_button'))
          .fontColor($r('app.color.accent_blue'))
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1).height(48)
          .borderRadius(24)
          .onClick(() => this.controller.close())
        Button($r('app.string.btn_delete'))
          .backgroundColor($r('app.color.bg_button'))
          .fontColor($r('app.color.accent_red'))
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1).height(48)
          .borderRadius(24)
          .onClick(() => {
            this.controller.close();
            if (this.onConfirm) this.onConfirm();
          })
      }
      .margin({ top: 12, left: 24, right: 24, bottom: 16 })
    }
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(20)
    .margin({ left: 8, right: 8, bottom: 8 })
    .width(344)
  }
}
