import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { OtpAccount, OtpType } from '../model/OtpAccount';

const TABLE = 'otp_account';
const CREATE_SQL = `CREATE TABLE IF NOT EXISTS ${TABLE} (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  note TEXT NOT NULL DEFAULT '',
  type TEXT NOT NULL,
  period INTEGER NOT NULL DEFAULT 30,
  digits INTEGER NOT NULL DEFAULT 6,
  algorithm TEXT NOT NULL DEFAULT 'SHA1',
  counter INTEGER NOT NULL DEFAULT 0,
  iconKey TEXT NOT NULL DEFAULT '',
  orderIndex INTEGER NOT NULL DEFAULT 0,
  createdAt INTEGER NOT NULL,
  updatedAt INTEGER NOT NULL
)`;

const CONFIG: relationalStore.StoreConfig = {
  name: 'rotor.db',
  securityLevel: relationalStore.SecurityLevel.S2
};

let storePromise: Promise<relationalStore.RdbStore> | null = null;

async function initStore(ctx: common.Context): Promise<relationalStore.RdbStore> {
  try {
    const s = await relationalStore.getRdbStore(ctx, CONFIG);
    try {
      await s.executeSql(CREATE_SQL);
    } catch (e) {
      console.error('[OtpAccountStore.getStore] executeSql failed', e);
    }
    return s;
  } catch (e) {
    console.error('[OtpAccountStore.initStore] getRdbStore failed', e);
    throw new Error(String(e));
  }
}

async function getStore(ctx: common.Context): Promise<relationalStore.RdbStore> {
  if (!storePromise) {
    storePromise = initStore(ctx);
  }
  return storePromise;
}

function rowToAccount(rows: relationalStore.ResultSet): OtpAccount {
  try {
    const algo = rows.getString(rows.getColumnIndex('algorithm'));
    return {
      id: rows.getString(rows.getColumnIndex('id')),
      name: rows.getString(rows.getColumnIndex('name')),
      note: rows.getString(rows.getColumnIndex('note')),
      type: rows.getString(rows.getColumnIndex('type')) === 'hotp' ? OtpType.HOTP : OtpType.TOTP,
      period: rows.getLong(rows.getColumnIndex('period')),
      digits: rows.getLong(rows.getColumnIndex('digits')),
      algorithm: (algo === 'SHA256' || algo === 'SHA512') ? algo : 'SHA1',
      counter: rows.getLong(rows.getColumnIndex('counter')),
      iconKey: rows.getString(rows.getColumnIndex('iconKey')),
      orderIndex: rows.getLong(rows.getColumnIndex('orderIndex')),
      createdAt: rows.getLong(rows.getColumnIndex('createdAt')),
      updatedAt: rows.getLong(rows.getColumnIndex('updatedAt'))
    };
  } catch (e) {
    console.error('[OtpAccountStore.rowToAccount] failed', e);
    // 返回安全默认值
    return {
      id: '',
      name: '',
      note: '',
      type: OtpType.TOTP,
      period: 30,
      digits: 6,
      algorithm: 'SHA1',
      counter: 0,
      iconKey: '',
      orderIndex: 0,
      createdAt: 0,
      updatedAt: 0
    };
  }
}

function toBucket(a: OtpAccount): relationalStore.ValuesBucket {
  return {
    'id': a.id, 'name': a.name, 'note': a.note, 'type': a.type,
    'period': a.period, 'digits': a.digits, 'algorithm': a.algorithm,
    'counter': a.counter, 'iconKey': a.iconKey, 'orderIndex': a.orderIndex,
    'createdAt': a.createdAt, 'updatedAt': a.updatedAt
  };
}

export class OtpAccountStore {
  static async insert(ctx: common.Context, a: OtpAccount): Promise<void> {
    try {
      const s = await getStore(ctx);
      await s.insert(TABLE, toBucket(a));
    } catch (e) {
      console.error('[OtpAccountStore.insert]', e);
    }
  }

  static async update(ctx: common.Context, a: OtpAccount): Promise<void> {
    try {
      const s = await getStore(ctx);
      const pred = new relationalStore.RdbPredicates(TABLE);
      pred.equalTo('id', a.id);
      await s.update(toBucket(a), pred);
    } catch (e) {
      console.error('[OtpAccountStore.update]', e);
    }
  }

  static async delete(ctx: common.Context, id: string): Promise<void> {
    try {
      const s = await getStore(ctx);
      const pred = new relationalStore.RdbPredicates(TABLE);
      pred.equalTo('id', id);
      await s.delete(pred);
    } catch (e) {
      console.error('[OtpAccountStore.delete]', e);
    }
  }

  static async listAll(ctx: common.Context): Promise<OtpAccount[]> {
    try {
      const s = await getStore(ctx);
      const pred = new relationalStore.RdbPredicates(TABLE);
      pred.orderByAsc('orderIndex');
      const rs = await s.query(pred);
      const out: OtpAccount[] = [];
      while (rs.goToNextRow()) {
        out.push(rowToAccount(rs));
      }
      rs.close();
      return out;
    } catch (e) {
      console.error('[OtpAccountStore.listAll]', e);
      return [];
    }
  }

  static async maxOrderIndex(ctx: common.Context): Promise<number> {
    try {
      const s = await getStore(ctx);
      const rs = await s.querySql(`SELECT MAX(orderIndex) AS m FROM ${TABLE}`);
      let m = 0;
      if (rs.goToNextRow()) {
        try {
          m = rs.getLong(rs.getColumnIndex('m')) || 0;
        } catch (e) {
          console.error('[OtpAccountStore.maxOrderIndex] getLong failed', e);
        }
      }
      rs.close();
      return m;
    } catch (e) {
      console.error('[OtpAccountStore.maxOrderIndex]', e);
      return 0;
    }
  }
}
