@CustomDialog
export struct DeleteConfirmDialog {
  controller: CustomDialogController;
  name: string = '';
  onConfirm?: () => void;

  build() {
    Column() {
      Text(`是否要删除 ${this.name}？`)
        .fontSize(16)
        .fontColor($r('app.color.text_primary'))
        .padding({ top: 24, bottom: 24 })
      Row() {
        Button($r('app.string.btn_cancel'))
          .backgroundColor(Color.Transparent)
          .fontColor($r('app.color.accent_blue'))
          .layoutWeight(1).height(48)
          .onClick(() => this.controller.close())
        Divider().vertical(true).strokeWidth(0.5).color($r('app.color.divider')).height(20)
        Button($r('app.string.btn_delete'))
          .backgroundColor(Color.Transparent)
          .fontColor($r('app.color.accent_red'))
          .layoutWeight(1).height(48)
          .onClick(() => {
            this.controller.close();
            if (this.onConfirm) this.onConfirm();
          })
      }
    }
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius({ topLeft: 16, topRight: 16 })
    .width('100%')
  }
}
