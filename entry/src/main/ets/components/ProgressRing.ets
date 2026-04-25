@Component
export struct ProgressRing {
  @Prop remaining: number = 30;
  @Prop period: number = 30;

  // 颜色分段：>10s 主色，3-10s 灰，<3s 红
  private color(): Resource {
    if (this.remaining < 3) {
      return $r('app.color.ring_danger');
    }
    if (this.remaining < 10) {
      return $r('app.color.ring_warn');
    }
    return $r('app.color.ring_normal');
  }

  build() {
    Stack() {
      Progress({ value: this.remaining, total: this.period, type: ProgressType.Ring })
        .width(24).height(24)
        .style({ strokeWidth: 2 })
        .color(this.color())
    }
  }
}
