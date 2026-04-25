@Component
export struct SearchBar {
  @Link query: string;
  onFocusIn?: () => void;

  build() {
    Search({ value: this.query, placeholder: $r('app.string.search_placeholder') })
      .height(40)
      .backgroundColor($r('app.color.bg_card_active'))
      .borderRadius(20)
      .placeholderColor($r('app.color.text_placeholder'))
      .textFont({ size: 14 })
      .onChange((v: string) => { this.query = v; })
      .onClick(() => { if (this.onFocusIn) this.onFocusIn(); })
  }
}
