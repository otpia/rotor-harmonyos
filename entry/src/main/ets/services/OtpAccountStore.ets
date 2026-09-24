import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { asset } from '@kit.AssetStoreKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { OtpAccount, OtpType, defaultAccount } from '../model/OtpAccount';

// AGC 云空间的数据类型名必须与表名一致，只允许字母和数字且以字母开头
export const ACCOUNT_TABLE = 'OtpAccount';

// 端云同步表的列不能带 NOT NULL，且只能新增不能修改删除
const CREATE_SQL = `CREATE TABLE IF NOT EXISTS ${ACCOUNT_TABLE} (
  id TEXT PRIMARY KEY,
  name TEXT DEFAULT '',
  note TEXT DEFAULT '',
  type TEXT DEFAULT 'totp',
  period INTEGER DEFAULT 30,
  digits INTEGER DEFAULT 6,
  algorithm TEXT DEFAULT 'SHA1',
  counter INTEGER DEFAULT 0,
  iconKey TEXT DEFAULT '',
  orderIndex INTEGER DEFAULT 0,
  createdAt INTEGER DEFAULT 0,
  updatedAt INTEGER DEFAULT 0,
  secret TEXT
)`;

// 结构版本：2 为账号表已是端云同步结构且密钥全部在 secret 列
const VERSION_CURRENT = 2;
// 旧账号表：列带 NOT NULL 约束，密钥在 Asset Kit
const LEGACY_TABLE = 'otp_account';
const LEGACY_COLUMNS = 'id, name, note, type, period, digits, algorithm, counter, iconKey, orderIndex, createdAt, updatedAt';
const LEGACY_ALIAS_PREFIX = 'otp_secret_';

const CONFIG: relationalStore.StoreConfig = {
  name: 'rotor.db',
  securityLevel: relationalStore.SecurityLevel.S3
};

let storePromise: Promise<relationalStore.RdbStore> | null = null;

function utf8(s: string): Uint8Array {
  return new util.TextEncoder('utf-8').encodeInto(s);
}

function legacyQuery(id: string): asset.AssetMap {
  const q: asset.AssetMap = new Map();
  q.set(asset.Tag.ALIAS, utf8(LEGACY_ALIAS_PREFIX + id));
  return q;
}

// 读 Asset Kit 中的旧密钥，不存在返回空串，其他错误抛出
async function readLegacySecret(id: string): Promise<string> {
  try {
    const q = legacyQuery(id);
    q.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
    const arr = await asset.query(q);
    if (arr.length === 0) {
      return '';
    }
    const sec = arr[0].get(asset.Tag.SECRET) as Uint8Array;
    return util.TextDecoder.create('utf-8').decodeToString(sec);
  } catch (e) {
    if ((e as BusinessError).code === asset.ErrorCode.NOT_FOUND) {
      return '';
    }
    throw new Error(String(e));
  }
}

async function removeLegacySecret(id: string): Promise<void> {
  try {
    await asset.remove(legacyQuery(id));
  } catch (e) {
    if ((e as BusinessError).code !== asset.ErrorCode.NOT_FOUND) {
      console.error('[OtpAccountStore.removeLegacySecret]', JSON.stringify(e));
    }
  }
}

async function tableExists(s: relationalStore.RdbStore, name: string): Promise<boolean> {
  try {
    const rs = await s.querySql('SELECT name FROM sqlite_master WHERE type = ? AND name = ?', ['table', name]);
    const found = rs.goToFirstRow();
    rs.close();
    return found;
  } catch (e) {
    throw new Error(String(e));
  }
}

async function hasColumn(s: relationalStore.RdbStore, table: string, column: string): Promise<boolean> {
  try {
    const rs = await s.querySql(`SELECT name FROM pragma_table_info('${table}') WHERE name = ?`, [column]);
    const found = rs.goToFirstRow();
    rs.close();
    return found;
  } catch (e) {
    throw new Error(String(e));
  }
}

// 在一个事务内建新表、搬入旧表数据并删除旧表，失败整体回滚；旧表已有 secret 列时一并搬入
async function moveLegacyTable(s: relationalStore.RdbStore): Promise<void> {
  const columns = (await hasColumn(s, LEGACY_TABLE, 'secret')) ? `${LEGACY_COLUMNS}, secret` : LEGACY_COLUMNS;
  let tx: relationalStore.Transaction | null = null;
  try {
    tx = await s.createTransaction();
    await tx.execute(CREATE_SQL);
    await tx.execute(`INSERT INTO ${ACCOUNT_TABLE} (${columns}) SELECT ${columns} FROM ${LEGACY_TABLE}`);
    await tx.execute(`DROP TABLE ${LEGACY_TABLE}`);
    await tx.commit();
  } catch (e) {
    if (tx !== null) {
      try {
        await tx.rollback();
      } catch (re) {
        console.error('[OtpAccountStore.moveLegacyTable] rollback', JSON.stringify(re));
      }
    }
    throw new Error(String(e));
  }
}

// 把 Asset Kit 中的密钥逐行写入 secret 列，写入成功才删除原条目；全部处理无异常时返回 true
async function migrateSecrets(s: relationalStore.RdbStore): Promise<boolean> {
  const ids: string[] = [];
  try {
    const rs = await s.querySql(`SELECT id FROM ${ACCOUNT_TABLE} WHERE secret IS NULL OR secret = ''`);
    while (rs.goToNextRow()) {
      ids.push(rs.getString(0));
    }
    rs.close();
  } catch (e) {
    console.error('[OtpAccountStore.migrateSecrets] list', JSON.stringify(e));
    return false;
  }
  let ok = true;
  let moved = 0;
  for (const id of ids) {
    try {
      const sec = await readLegacySecret(id);
      if (sec.length === 0) {
        continue;
      }
      const pred = new relationalStore.RdbPredicates(ACCOUNT_TABLE);
      pred.equalTo('id', id);
      const bucket: relationalStore.ValuesBucket = { 'secret': sec };
      const n = await s.update(bucket, pred);
      if (n === 1) {
        await removeLegacySecret(id);
        moved += 1;
      } else {
        ok = false;
      }
    } catch (e) {
      console.error('[OtpAccountStore.migrateSecrets]', id, JSON.stringify(e));
      ok = false;
    }
  }
  console.info(`[OtpAccountStore.migrateSecrets] moved ${moved} of ${ids.length}, ok=${ok}`);
  return ok;
}

// 按表的实际状态迁移：没有新表时从旧表搬数据或新建，再把 Asset Kit 中的密钥补进 secret 列，全部完成才记版本
async function migrate(s: relationalStore.RdbStore): Promise<void> {
  try {
    const hasTable = await tableExists(s, ACCOUNT_TABLE);
    if (hasTable && s.version >= VERSION_CURRENT) {
      return;
    }
    if (!hasTable) {
      if (await tableExists(s, LEGACY_TABLE)) {
        await moveLegacyTable(s);
        console.info('[OtpAccountStore.migrate] legacy table moved');
      } else {
        await s.executeSql(CREATE_SQL);
      }
    }
    if (await migrateSecrets(s)) {
      s.version = VERSION_CURRENT;
      console.info(`[OtpAccountStore.migrate] version -> ${VERSION_CURRENT}`);
    }
  } catch (e) {
    console.error('[OtpAccountStore.migrate]', JSON.stringify(e));
  }
}

async function openStore(ctx: common.Context): Promise<relationalStore.RdbStore> {
  try {
    return await relationalStore.getRdbStore(ctx, CONFIG);
  } catch (e) {
    console.error('[OtpAccountStore.openStore]', JSON.stringify(e));
    throw new Error(String(e));
  }
}

async function initStore(ctx: common.Context): Promise<relationalStore.RdbStore> {
  const s = await openStore(ctx);
  await migrate(s);
  return s;
}

function getStore(ctx: common.Context): Promise<relationalStore.RdbStore> {
  if (storePromise === null) {
    storePromise = initStore(ctx);
  }
  return storePromise;
}

function colString(rs: relationalStore.ResultSet, name: string, def: string): string {
  try {
    const i = rs.getColumnIndex(name);
    return i < 0 || rs.isColumnNull(i) ? def : rs.getString(i);
  } catch (e) {
    console.error('[OtpAccountStore.colString]', name, JSON.stringify(e));
    return def;
  }
}

function colNumber(rs: relationalStore.ResultSet, name: string, def: number): number {
  try {
    const i = rs.getColumnIndex(name);
    return i < 0 || rs.isColumnNull(i) ? def : rs.getLong(i);
  } catch (e) {
    console.error('[OtpAccountStore.colNumber]', name, JSON.stringify(e));
    return def;
  }
}

// 云端同步下来的行可能有空列，逐列按默认值兜底
function rowToAccount(rs: relationalStore.ResultSet): OtpAccount {
  const a = defaultAccount();
  a.id = colString(rs, 'id', '');
  a.name = colString(rs, 'name', '');
  a.note = colString(rs, 'note', '');
  a.type = colString(rs, 'type', 'totp') === 'hotp' ? OtpType.HOTP : OtpType.TOTP;
  a.period = colNumber(rs, 'period', 30);
  a.digits = colNumber(rs, 'digits', 6);
  const algo = colString(rs, 'algorithm', 'SHA1');
  a.algorithm = (algo === 'SHA256' || algo === 'SHA512') ? algo : 'SHA1';
  a.counter = colNumber(rs, 'counter', 0);
  a.iconKey = colString(rs, 'iconKey', '');
  a.orderIndex = colNumber(rs, 'orderIndex', 0);
  a.createdAt = colNumber(rs, 'createdAt', 0);
  a.updatedAt = colNumber(rs, 'updatedAt', 0);
  a.secret = colString(rs, 'secret', '');
  return a;
}

function toBucket(a: OtpAccount): relationalStore.ValuesBucket {
  return {
    'id': a.id, 'name': a.name, 'note': a.note, 'type': a.type,
    'period': a.period, 'digits': a.digits, 'algorithm': a.algorithm,
    'counter': a.counter, 'iconKey': a.iconKey, 'orderIndex': a.orderIndex,
    'createdAt': a.createdAt, 'updatedAt': a.updatedAt, 'secret': a.secret
  };
}

export class OtpAccountStore {
  // 迁移完成后的数据库实例，端云同步与本类共用
  static store(ctx: common.Context): Promise<relationalStore.RdbStore> {
    return getStore(ctx);
  }

  static async insert(ctx: common.Context, a: OtpAccount): Promise<void> {
    try {
      const s = await getStore(ctx);
      await s.insert(ACCOUNT_TABLE, toBucket(a));
    } catch (e) {
      console.error('[OtpAccountStore.insert]', e);
    }
  }

  static async update(ctx: common.Context, a: OtpAccount): Promise<void> {
    try {
      const s = await getStore(ctx);
      const pred = new relationalStore.RdbPredicates(ACCOUNT_TABLE);
      pred.equalTo('id', a.id);
      await s.update(toBucket(a), pred);
    } catch (e) {
      console.error('[OtpAccountStore.update]', e);
    }
  }

  static async delete(ctx: common.Context, id: string): Promise<void> {
    try {
      const s = await getStore(ctx);
      const pred = new relationalStore.RdbPredicates(ACCOUNT_TABLE);
      pred.equalTo('id', id);
      await s.delete(pred);
    } catch (e) {
      console.error('[OtpAccountStore.delete]', e);
    }
  }

  static async listAll(ctx: common.Context): Promise<OtpAccount[]> {
    try {
      const s = await getStore(ctx);
      const pred = new relationalStore.RdbPredicates(ACCOUNT_TABLE);
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
      const rs = await s.querySql(`SELECT MAX(orderIndex) AS m FROM ${ACCOUNT_TABLE}`);
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
