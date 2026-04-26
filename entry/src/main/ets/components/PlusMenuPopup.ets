@Component
export struct PlusMenuPopup {
  onInputSecret?: () => void;
  onScanQr?: () => void;

  @Builder Item(text: Resource, onTap: () => void) {
    Text(text)
      .fontSize(18).fontColor($r('app.color.text_primary'))
      .height(25)
      .padding({ left: 16, right: 16 })
      .width('100%')
      .onClick(() => onTap())
  }

  build() {
    Column({ space: 13 }) {
      this.Item($r('app.string.menu_input_secret'), () => { if (this.onInputSecret) this.onInputSecret(); })
      Divider().color($r('app.color.divider')).strokeWidth(1).margin({ left: 16, right: 16 })
      this.Item($r('app.string.menu_scan_qr'), () => { if (this.onScanQr) this.onScanQr(); })
    }
    .padding({ top: 16, bottom: 16 })
    .backgroundColor(Color.White)
    .borderRadius(18)
    .width(180)
    .shadow({ radius: 12, color: '#1F000000', offsetY: 4 })
  }
}
