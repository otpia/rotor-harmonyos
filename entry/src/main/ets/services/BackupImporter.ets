import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { defaultAccount, OtpAccount, OtpType } from '../model/OtpAccount';
import { OtpAccountStore } from './OtpAccountStore';
import { SecretVault } from './SecretVault';
import { existingSecretSet } from './AccountDedup';
import { decryptBackup, BackupFile } from '../utils/BackupCrypto';

interface BackupAccount {
  name: string;
  note: string;
  type: string;
  period: number;
  digits: number;
  algorithm: string;
  counter: number;
  iconKey: string;
  secret: string;
}

interface BackupPlain {
  accounts: BackupAccount[];
}

export async function importBackup(ctx: common.UIAbilityContext, uri: string, password: string): Promise<number> {
  const f = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
  let text = '';
  try {
    const stat = fileIo.statSync(f.fd);
    const size = stat.size;
    const buf = new ArrayBuffer(size);
    fileIo.readSync(f.fd, buf);
    text = util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(buf));
  } finally {
    fileIo.closeSync(f);
  }
  const file: BackupFile = JSON.parse(text) as BackupFile;
  const plainText = await decryptBackup(password, file);
  const plain: BackupPlain = JSON.parse(plainText) as BackupPlain;

  const existingSet = await existingSecretSet(ctx);
  let order = await OtpAccountStore.maxOrderIndex(ctx);
  let count = 0;
  for (const a of plain.accounts) {
    if (existingSet.has(a.secret)) continue;
    try {
      const acct: OtpAccount = defaultAccount();
      acct.id = util.generateRandomUUID(false);
      acct.name = a.name || '';
      acct.note = a.note || '';
      acct.type = a.type === 'hotp' ? OtpType.HOTP : OtpType.TOTP;
      acct.period = a.period || 30;
      acct.digits = a.digits || 6;
      acct.algorithm = (a.algorithm === 'SHA256' || a.algorithm === 'SHA512')
        ? (a.algorithm as 'SHA256' | 'SHA512')
        : 'SHA1';
      acct.counter = a.counter || 0;
      acct.iconKey = a.iconKey || '';
      order += 1;
      acct.orderIndex = order;
      const now = Date.now();
      acct.createdAt = now;
      acct.updatedAt = now;
      await SecretVault.put(acct.id, a.secret);
      await OtpAccountStore.insert(ctx, acct);
      existingSet.add(a.secret);
      count += 1;
    } catch (e) {
      console.error('[BackupImporter.insert]', e);
    }
  }
  return count;
}
