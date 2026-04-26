@Component
export struct ProgressRing {
  @Prop period: number = 30;
  @State remaining: number = 30;
  private timerId: number = -1;

  aboutToAppear(): void {
    this.tick();
    this.timerId = setInterval(() => this.tick(), 50);
  }

  aboutToDisappear(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  private tick(): void {
    const sec = Date.now() / 1000;
    this.remaining = this.period - (sec % this.period);
  }

  // 颜色分段：>5s 主色，≤5s 红
  private color(): Resource {
    return this.remaining <= 5 ? $r('app.color.ring_danger') : $r('app.color.ring_normal');
  }

  build() {
    Stack() {
      // 仅画剩余时间弧体；scale x=-1 让缺口从 12 点起顺时针扩张
      Progress({ value: this.remaining, total: this.period, type: ProgressType.Ring })
        .width(36).height(36)
        .style({ strokeWidth: 3, enableSmoothEffect: false })
        .backgroundColor(Color.Transparent)
        .color(this.color())
        .scale({ x: -1, y: 1 })
    }
    .width(40).height(40)
  }
}
