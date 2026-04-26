@CustomDialog
export struct PasswordDialog {
  controller: CustomDialogController;
  title: ResourceStr = '';
  needConfirm: boolean = true;
  onSubmit?: (pwd: string) => void;
  @State pwd: string = '';
  @State pwd2: string = '';
  @State error: string = '';

  private submit(): void {
    if (this.pwd.length < 6) {
      this.error = '密码至少 6 位';
      return;
    }
    if (this.needConfirm && this.pwd !== this.pwd2) {
      this.error = '两次密码不一致';
      return;
    }
    const v = this.pwd;
    this.controller.close();
    if (this.onSubmit) this.onSubmit(v);
  }

  build() {
    Column() {
      Text(this.title)
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .alignSelf(ItemAlign.Start)
        .padding({ top: 24, left: 24, bottom: 16 })

      TextInput({ placeholder: $r('app.string.export_password_hint'), text: this.pwd })
        .type(InputType.Password)
        .fontSize(16)
        .height(48)
        .backgroundColor($r('app.color.bg_button'))
        .borderRadius(12)
        .padding({ left: 16, right: 16 })
        .margin({ left: 24, right: 24, bottom: 8 })
        .onChange((v: string) => { this.pwd = v; this.error = ''; })

      if (this.needConfirm) {
        TextInput({ placeholder: $r('app.string.export_password_confirm'), text: this.pwd2 })
          .type(InputType.Password)
          .fontSize(16)
          .height(48)
          .backgroundColor($r('app.color.bg_button'))
          .borderRadius(12)
          .padding({ left: 16, right: 16 })
          .margin({ left: 24, right: 24, bottom: 8 })
          .onChange((v: string) => { this.pwd2 = v; this.error = ''; })
      }

      if (this.error) {
        Text(this.error)
          .fontSize(13).fontColor($r('app.color.accent_red'))
          .padding({ left: 24, right: 24, bottom: 4 })
          .alignSelf(ItemAlign.Start)
      }

      Row({ space: 8 }) {
        Button($r('app.string.btn_cancel'))
          .backgroundColor($r('app.color.bg_button'))
          .fontColor($r('app.color.accent_blue'))
          .fontSize(18).fontWeight(FontWeight.Medium)
          .layoutWeight(1).height(48)
          .borderRadius(24)
          .onClick(() => this.controller.close())
        Button($r('app.string.btn_save'))
          .backgroundColor($r('app.color.bg_button'))
          .fontColor($r('app.color.accent_blue'))
          .fontSize(18).fontWeight(FontWeight.Medium)
          .layoutWeight(1).height(48)
          .borderRadius(24)
          .onClick(() => this.submit())
      }
      .margin({ top: 8, left: 24, right: 24, bottom: 16 })
    }
    .backgroundColor($r('app.color.bg_dialog'))
    .borderRadius(20)
    .margin({ left: 8, right: 8, bottom: 8 })
    .width(344)
  }
}
