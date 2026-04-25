@Component
export struct PlusMenuPopup {
  onInputSecret?: () => void;
  onScanQr?: () => void;

  @Builder Item(text: Resource, onTap: () => void) {
    Text(text)
      .fontSize(16).fontColor($r('app.color.text_primary'))
      .padding({ top: 12, bottom: 12, left: 16, right: 16 })
      .width('100%')
      .onClick(() => onTap())
  }

  build() {
    Column() {
      this.Item($r('app.string.menu_input_secret'), () => { if (this.onInputSecret) this.onInputSecret(); })
      Divider().color($r('app.color.divider')).strokeWidth(0.5)
      this.Item($r('app.string.menu_scan_qr'), () => { if (this.onScanQr) this.onScanQr(); })
    }
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(8)
    .width(160)
    .shadow({ radius: 12, color: '#1F000000', offsetY: 4 })
  }
}
