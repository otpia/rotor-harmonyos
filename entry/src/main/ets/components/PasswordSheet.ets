// 半模态内的备份密码输入区，标题由 bindSheet 的 title 提供
@Component
export struct PasswordSheet {
  needConfirm: boolean = true;
  placeholder: ResourceStr = '';
  submitLabel: ResourceStr = $r('app.string.btn_save');
  onSubmit?: (pwd: string) => void;
  @State pwd: string = '';
  @State pwd2: string = '';
  @State error: Resource | null = null;

  private submit(): void {
    if (this.pwd.length < 6) {
      this.error = $r('app.string.password_too_short');
      return;
    }
    if (this.needConfirm && this.pwd !== this.pwd2) {
      this.error = $r('app.string.password_mismatch');
      return;
    }
    if (this.onSubmit) {
      this.onSubmit(this.pwd);
    }
  }

  build() {
    Column({ space: 12 }) {
      TextInput({ placeholder: this.placeholder })
        .type(InputType.Password)
        .height(40)
        .onChange((v: string) => {
          this.pwd = v;
          this.error = null;
        })

      if (this.needConfirm) {
        TextInput({ placeholder: $r('app.string.export_password_confirm') })
          .type(InputType.Password)
          .height(40)
          .onChange((v: string) => {
            this.pwd2 = v;
            this.error = null;
          })
      }

      if (this.error !== null) {
        Text(this.error)
          .fontSize($r('sys.float.Body_S'))
          .fontColor($r('sys.color.warning'))
          .width('100%')
      }

      Button(this.submitLabel)
        .width('100%')
        .margin({ top: 8 })
        .onClick(() => this.submit())
    }
    .padding({ left: 16, right: 16, top: 8, bottom: 24 })
    .width('100%')
  }
}
