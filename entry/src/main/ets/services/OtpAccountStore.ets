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

function getStore(ctx: common.Context): Promise<relationalStore.RdbStore> {
  if (!storePromise) {
    storePromise = relationalStore.getRdbStore(ctx, CONFIG).then(async (s) => {
      await s.executeSql(CREATE_SQL);
      return s;
    });
  }
  return storePromise;
}

function rowToAccount(rows: relationalStore.ResultSet): OtpAccount {
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
    const s = await getStore(ctx);
    await s.insert(TABLE, toBucket(a));
  }
  static async update(ctx: common.Context, a: OtpAccount): Promise<void> {
    const s = await getStore(ctx);
    const pred = new relationalStore.RdbPredicates(TABLE);
    pred.equalTo('id', a.id);
    await s.update(toBucket(a), pred);
  }
  static async delete(ctx: common.Context, id: string): Promise<void> {
    const s = await getStore(ctx);
    const pred = new relationalStore.RdbPredicates(TABLE);
    pred.equalTo('id', id);
    await s.delete(pred);
  }
  static async listAll(ctx: common.Context): Promise<OtpAccount[]> {
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
  }
  static async maxOrderIndex(ctx: common.Context): Promise<number> {
    const s = await getStore(ctx);
    const rs = await s.querySql(`SELECT MAX(orderIndex) AS m FROM ${TABLE}`);
    let m = 0;
    if (rs.goToNextRow()) {
      m = rs.getLong(rs.getColumnIndex('m')) || 0;
    }
    rs.close();
    return m;
  }
}
