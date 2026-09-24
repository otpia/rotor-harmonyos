import { preferences, relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { connection } from '@kit.NetworkKit';
import { ACCOUNT_TABLE, OtpAccountStore } from './OtpAccountStore';

export enum CloudSyncState {
  OFF = 0,
  SYNCING = 1,
  SYNCED = 2,
  DISCONNECTED = 3
}

export interface CloudSyncStatus {
  state: CloudSyncState;
  // 最近一次同步的结束码，取值为 relationalStore.ProgressCode 或下面两个常量
  code: number;
  online: boolean;
  lastSyncAt: number;
}

// 本进程内尚未完成首次同步
export const CODE_PENDING = -2;
// 同步调用抛出异常或超时
export const CODE_FAILED = -1;

const PREFS_NAME = 'rotor_settings';
const KEY_ENABLED = 'cloudSyncEnabled';
const KEY_LAST_SYNC = 'lastSyncAt';
const KEY_GUIDE_SHOWN = 'syncGuideShown';
// 自动触发的同步至少间隔 30 秒，避免被云端限流
const DEBOUNCE_MS = 30000;
// 进度回调迟迟不报结束时按失败处理
const SYNC_TIMEOUT_MS = 60000;

type StatusListener = (s: CloudSyncStatus) => void;
type ChangeListener = () => void;

export function syncStateSymbol(state: CloudSyncState): Resource {
  if (state === CloudSyncState.SYNCED) {
    return $r('sys.symbol.checkmark_icloud_fill');
  }
  if (state === CloudSyncState.SYNCING) {
    return $r('sys.symbol.icloud_badge_arrow_2_circlepath');
  }
  if (state === CloudSyncState.DISCONNECTED) {
    return $r('sys.symbol.icloud_slash');
  }
  return $r('sys.symbol.icloud');
}

function onConfig(): relationalStore.DistributedConfig {
  const c: relationalStore.DistributedConfig = { autoSync: true, enableCloud: true };
  return c;
}

function offConfig(): relationalStore.DistributedConfig {
  const c: relationalStore.DistributedConfig = { autoSync: false, enableCloud: false };
  return c;
}

class CloudSync {
  private prefs: preferences.Preferences | null = null;
  private rdb: relationalStore.RdbStore | null = null;
  private inited: boolean = false;
  private enabled: boolean = false;
  private syncing: boolean = false;
  private online: boolean = true;
  private code: number = CODE_PENDING;
  private lastSyncAt: number = 0;
  private lastRunAt: number = 0;
  private runId: number = 0;
  private timer: number = -1;
  private observing: boolean = false;
  private net: connection.NetConnection | null = null;
  private statusListeners: Set<StatusListener> = new Set();
  private changeListeners: Set<ChangeListener> = new Set();
  private cloudObserver: (accounts: Array<string>) => void = (_accounts: Array<string>) => {
    this.emitChange();
  };

  status(): CloudSyncStatus {
    let state = CloudSyncState.OFF;
    if (this.enabled) {
      if (this.syncing || (this.code === CODE_PENDING && this.online)) {
        state = CloudSyncState.SYNCING;
      } else if (this.online && this.code === relationalStore.ProgressCode.SUCCESS) {
        state = CloudSyncState.SYNCED;
      } else {
        state = CloudSyncState.DISCONNECTED;
      }
    }
    const s: CloudSyncStatus = { state: state, code: this.code, online: this.online, lastSyncAt: this.lastSyncAt };
    return s;
  }

  isEnabled(): boolean {
    return this.enabled;
  }

  onStatusChange(cb: StatusListener): () => void {
    this.statusListeners.add(cb);
    return () => {
      this.statusListeners.delete(cb);
    };
  }

  onCloudDataChange(cb: ChangeListener): () => void {
    this.changeListeners.add(cb);
    return () => {
      this.changeListeners.delete(cb);
    };
  }

  // 冷启动调用一次：按持久化的开关状态重新下发分布式表配置，开启时同步一次
  async init(ctx: common.Context): Promise<void> {
    if (this.inited) {
      this.emitStatus();
      return;
    }
    this.inited = true;
    try {
      const p = await this.prefsOf(ctx);
      this.enabled = p.getSync(KEY_ENABLED, false) as boolean;
      this.lastSyncAt = p.getSync(KEY_LAST_SYNC, 0) as number;
      const turnedOff = !this.enabled && p.hasSync(KEY_ENABLED);
      const store = await OtpAccountStore.store(ctx);
      this.rdb = store;
      if (this.enabled) {
        await store.setDistributedTables([ACCOUNT_TABLE], relationalStore.DistributedType.DISTRIBUTED_CLOUD,
          onConfig());
        this.observe();
        this.startNet(ctx);
        this.emitStatus();
        this.syncNow(ctx, false);
      } else if (turnedOff) {
        await store.setDistributedTables([ACCOUNT_TABLE], relationalStore.DistributedType.DISTRIBUTED_CLOUD,
          offConfig());
      }
    } catch (e) {
      console.error('[CloudSyncService.init]', JSON.stringify(e));
      this.code = CODE_FAILED;
    }
    this.emitStatus();
  }

  async enable(ctx: common.Context): Promise<void> {
    try {
      const store = await OtpAccountStore.store(ctx);
      this.rdb = store;
      await store.setDistributedTables([ACCOUNT_TABLE], relationalStore.DistributedType.DISTRIBUTED_CLOUD,
        onConfig());
      await this.saveEnabled(ctx, true);
    } catch (e) {
      console.error('[CloudSyncService.enable]', JSON.stringify(e));
      throw new Error(String(e));
    }
    this.enabled = true;
    this.code = CODE_PENDING;
    this.observe();
    this.startNet(ctx);
    this.emitStatus();
    this.syncNow(ctx, true);
  }

  // 只停止同步，本地与云端数据都保留
  async disable(ctx: common.Context): Promise<void> {
    try {
      const store = await OtpAccountStore.store(ctx);
      await store.setDistributedTables([ACCOUNT_TABLE], relationalStore.DistributedType.DISTRIBUTED_CLOUD,
        offConfig());
      await this.saveEnabled(ctx, false);
    } catch (e) {
      console.error('[CloudSyncService.disable]', JSON.stringify(e));
      throw new Error(String(e));
    }
    this.enabled = false;
    this.syncing = false;
    this.runId += 1;
    this.clearTimer();
    this.unobserve();
    this.stopNet();
    this.emitStatus();
  }

  // manual 为 false 时受 30 秒防抖约束；以进度回调的 SYNC_FINISH 作为结束
  async syncNow(ctx: common.Context, manual: boolean): Promise<void> {
    if (!this.enabled || this.syncing) {
      return;
    }
    const now = Date.now();
    if (!manual && now - this.lastRunAt < DEBOUNCE_MS) {
      return;
    }
    this.lastRunAt = now;
    this.syncing = true;
    this.runId += 1;
    const id = this.runId;
    this.emitStatus();
    this.clearTimer();
    this.timer = setTimeout(() => {
      this.finish(ctx, id, CODE_FAILED);
    }, SYNC_TIMEOUT_MS);
    try {
      const store = await OtpAccountStore.store(ctx);
      await store.cloudSync(relationalStore.SyncMode.SYNC_MODE_TIME_FIRST, [ACCOUNT_TABLE],
        (p: relationalStore.ProgressDetails) => {
          console.info('[CloudSyncService.progress]', JSON.stringify(p));
          if (p.schedule === relationalStore.Progress.SYNC_FINISH) {
            this.finish(ctx, id, p.code);
          }
        });
    } catch (e) {
      console.error('[CloudSyncService.syncNow]', JSON.stringify(e));
      this.finish(ctx, id, CODE_FAILED);
    }
  }

  async guideShown(ctx: common.Context): Promise<boolean> {
    try {
      const p = await this.prefsOf(ctx);
      return p.getSync(KEY_GUIDE_SHOWN, false) as boolean;
    } catch (e) {
      console.error('[CloudSyncService.guideShown]', JSON.stringify(e));
      return false;
    }
  }

  async markGuideShown(ctx: common.Context): Promise<void> {
    try {
      const p = await this.prefsOf(ctx);
      p.putSync(KEY_GUIDE_SHOWN, true);
      await p.flush();
    } catch (e) {
      console.error('[CloudSyncService.markGuideShown]', JSON.stringify(e));
    }
  }

  // 应用销毁时调用：注销网络监听与云端变更订阅，下次 init 重新建立
  release(): void {
    this.clearTimer();
    this.unobserve();
    this.stopNet();
    this.syncing = false;
    this.inited = false;
  }

  private finish(ctx: common.Context, id: number, code: number): void {
    if (id !== this.runId || !this.syncing) {
      return;
    }
    this.clearTimer();
    this.syncing = false;
    this.code = code;
    console.info(`[CloudSyncService] sync finished, code=${code}`);
    if (code === relationalStore.ProgressCode.SUCCESS) {
      this.lastSyncAt = Date.now();
      this.saveLastSync(ctx, this.lastSyncAt);
      this.emitChange();
    }
    this.emitStatus();
  }

  private clearTimer(): void {
    if (this.timer >= 0) {
      clearTimeout(this.timer);
      this.timer = -1;
    }
  }

  private emitStatus(): void {
    const s = this.status();
    this.statusListeners.forEach((cb: StatusListener) => {
      cb(s);
    });
  }

  private emitChange(): void {
    this.changeListeners.forEach((cb: ChangeListener) => {
      cb();
    });
  }

  private observe(): void {
    const rdb = this.rdb;
    if (this.observing || rdb === null) {
      return;
    }
    try {
      rdb.on('dataChange', relationalStore.SubscribeType.SUBSCRIBE_TYPE_CLOUD, this.cloudObserver);
      this.observing = true;
    } catch (e) {
      console.error('[CloudSyncService.observe]', JSON.stringify(e));
    }
  }

  private unobserve(): void {
    const rdb = this.rdb;
    if (!this.observing || rdb === null) {
      return;
    }
    this.observing = false;
    try {
      rdb.off('dataChange', relationalStore.SubscribeType.SUBSCRIBE_TYPE_CLOUD, this.cloudObserver);
    } catch (e) {
      console.error('[CloudSyncService.unobserve]', JSON.stringify(e));
    }
  }

  // 监听默认网络：断开时立即显示「与云断开」，恢复时补一次同步
  private startNet(ctx: common.Context): void {
    if (this.net !== null) {
      return;
    }
    try {
      this.online = connection.hasDefaultNetSync();
    } catch (e) {
      console.error('[CloudSyncService.hasDefaultNet]', JSON.stringify(e));
    }
    try {
      const conn = connection.createNetConnection();
      conn.on('netAvailable', (_h: connection.NetHandle) => {
        this.online = true;
        this.emitStatus();
        this.syncNow(ctx, false);
      });
      conn.on('netLost', (_h: connection.NetHandle) => {
        this.online = false;
        this.emitStatus();
      });
      conn.register((err: BusinessError) => {
        if (err) {
          console.error('[CloudSyncService.register]', JSON.stringify(err));
        }
      });
      this.net = conn;
    } catch (e) {
      console.error('[CloudSyncService.startNet]', JSON.stringify(e));
    }
  }

  private stopNet(): void {
    const conn = this.net;
    if (conn === null) {
      return;
    }
    this.net = null;
    try {
      conn.unregister((err: BusinessError) => {
        if (err) {
          console.error('[CloudSyncService.unregister]', JSON.stringify(err));
        }
      });
    } catch (e) {
      console.error('[CloudSyncService.stopNet]', JSON.stringify(e));
    }
  }

  private async prefsOf(ctx: common.Context): Promise<preferences.Preferences> {
    let p = this.prefs;
    if (p === null) {
      try {
        const opts: preferences.Options = { name: PREFS_NAME };
        p = await preferences.getPreferences(ctx, opts);
      } catch (e) {
        throw new Error(String(e));
      }
      this.prefs = p;
    }
    return p;
  }

  private async saveEnabled(ctx: common.Context, on: boolean): Promise<void> {
    try {
      const p = await this.prefsOf(ctx);
      p.putSync(KEY_ENABLED, on);
      await p.flush();
    } catch (e) {
      throw new Error(String(e));
    }
  }

  private async saveLastSync(ctx: common.Context, at: number): Promise<void> {
    try {
      const p = await this.prefsOf(ctx);
      p.putSync(KEY_LAST_SYNC, at);
      await p.flush();
    } catch (e) {
      console.error('[CloudSyncService.saveLastSync]', JSON.stringify(e));
    }
  }
}

export const CloudSyncService: CloudSync = new CloudSync();
