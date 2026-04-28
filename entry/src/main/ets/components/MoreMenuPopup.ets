@Component
export struct MoreMenuPopup {
  onImport?: () => void;
  onEdit?: () => void;
  onAbout?: () => void;

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
      this.Item($r('app.string.menu_import'), () => { if (this.onImport) this.onImport(); })
      Divider().color($r('app.color.divider')).strokeWidth(1).margin({ left: 16, right: 16 })
      this.Item($r('app.string.btn_edit'), () => { if (this.onEdit) this.onEdit(); })
      Divider().color($r('app.color.divider')).strokeWidth(1).margin({ left: 16, right: 16 })
      this.Item($r('app.string.menu_about'), () => { if (this.onAbout) this.onAbout(); })
    }
    .padding({ top: 16, bottom: 16 })
    .backgroundColor($r('app.color.bg_dialog'))
    .borderRadius(18)
    .width(180)
    .shadow({ radius: 12, color: '#1F000000', offsetY: 4 })
  }
}
