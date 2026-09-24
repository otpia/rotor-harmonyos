import { scanCore, scanBarcode } from '@kit.ScanKit';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { parseOtpAuth, ParsedOtpAuth } from '../utils/OtpAuthUri';
import { isMigrationUri, parseMigrationUri } from '../utils/MigrationUri';
import { OtpAccountStore } from './OtpAccountStore';
import { existingSecretSet } from './AccountDedup';

export enum ScanResultKind {
  CANCELLED = 0,
  UNRECOGNIZED = 1,
  NO_ACCOUNT = 2,
  // 单个 otpauth 账号，需进入编辑页确认
  SINGLE = 3,
  // Google Authenticator 迁移二维码，已直接落库
  IMPORTED = 4
}

export class ScanResult {
  kind: ScanResultKind = ScanResultKind.CANCELLED;
  parsed: ParsedOtpAuth | null = null;
  importedCount: number = 0;
}

// 拉起 Scan Kit 默认界面扫码（相机由系统预授权），解析结果交给调用方处理
export async function scanQrCode(ctx: common.UIAbilityContext): Promise<ScanResult> {
  const result = new ScanResult();
  let text = '';
  try {
    const opts: scanBarcode.ScanOptions = {
      scanTypes: [scanCore.ScanType.QR_CODE],
      enableMultiMode: false,
      enableAlbum: true
    };
    const scanned = await scanBarcode.startScanForResult(ctx, opts);
    text = scanned.originalValue || '';
  } catch (e) {
    console.error('[ScanService.scan]', e);
    return result;
  }

  if (isMigrationUri(text)) {
    return importMigration(ctx, text, result);
  }
  try {
    result.parsed = parseOtpAuth(text);
    result.kind = ScanResultKind.SINGLE;
  } catch (e) {
    console.error('[ScanService.parse]', e);
    result.kind = ScanResultKind.UNRECOGNIZED;
  }
  return result;
}

async function importMigration(ctx: common.UIAbilityContext, uri: string, result: ScanResult): Promise<ScanResult> {
  let items: ParsedOtpAuth[] = [];
  try {
    items = parseMigrationUri(uri);
  } catch (e) {
    console.error('[ScanService.importMigration] parse failed', e);
    result.kind = ScanResultKind.UNRECOGNIZED;
    return result;
  }
  if (items.length === 0) {
    result.kind = ScanResultKind.NO_ACCOUNT;
    return result;
  }
  try {
    const existingSet = await existingSecretSet(ctx);
    let imported = 0;
    let order = await OtpAccountStore.maxOrderIndex(ctx);
    for (const item of items) {
      if (existingSet.has(item.secret)) {
        continue;
      }
      try {
        const acct = item.account;
        acct.id = util.generateRandomUUID(false);
        acct.name = item.name;
        acct.note = item.note;
        order += 1;
        acct.orderIndex = order;
        const now = Date.now();
        acct.createdAt = now;
        acct.updatedAt = now;
        acct.secret = item.secret;
        await OtpAccountStore.insert(ctx, acct);
        existingSet.add(item.secret);
        imported += 1;
      } catch (e) {
        console.error('[ScanService.importMigration] insert failed', e);
      }
    }
    result.kind = ScanResultKind.IMPORTED;
    result.importedCount = imported;
  } catch (e) {
    console.error('[ScanService.importMigration]', e);
    result.kind = ScanResultKind.UNRECOGNIZED;
  }
  return result;
}
