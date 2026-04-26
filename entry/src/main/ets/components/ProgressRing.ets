@Component
export struct ProgressRing {
  @Prop remaining: number = 30;
  @Prop period: number = 30;

  // 颜色分段：>5s 主色，≤5s 红
  private color(): Resource {
    return this.remaining <= 5 ? $r('app.color.ring_danger') : $r('app.color.ring_normal');
  }

  build() {
    Stack() {
      Progress({ value: this.remaining, total: this.period, type: ProgressType.Ring })
        .width(36).height(36)
        .style({ strokeWidth: 3, enableSmoothEffect: false })
        .backgroundColor(Color.Transparent)
        .color(this.color())
    }
    .width(40).height(40)
  }
}
