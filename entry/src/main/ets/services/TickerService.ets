type Listener = (nowMs: number) => void;

class Ticker {
  private timerId: number = -1;
  private listeners: Set<Listener> = new Set();

  subscribe(l: Listener): () => void {
    this.listeners.add(l);
    if (this.timerId < 0) {
      this.timerId = setInterval(() => {
        const now = Date.now();
        this.listeners.forEach(fn => fn(now));
      }, 1000);
    }
    return () => this.unsubscribe(l);
  }

  unsubscribe(l: Listener): void {
    this.listeners.delete(l);
    if (this.listeners.size === 0 && this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }
}

export const TickerService: Ticker = new Ticker();
