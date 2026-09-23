import { scanCore, scanBarcode } from '@kit.ScanKit';
import { abilityAccessCtrl, common, PermissionRequestResult, Permissions } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { parseOtpAuth, ParsedOtpAuth } from '../utils/OtpAuthUri';
import { isMigrationUri, parseMigrationUri } from '../utils/MigrationUri';
import { OtpAccountStore } from './OtpAccountStore';
import { SecretVault } from './SecretVault';
import { existingSecretSet } from './AccountDedup';

export enum ScanResultKind {
  CANCELLED = 0,
  PERMISSION_DENIED = 1,
  UNRECOGNIZED = 2,
  NO_ACCOUNT = 3,
  // 单个 otpauth 账号，需进入编辑页确认
  SINGLE = 4,
  // Google Authenticator 迁移二维码，已直接落库
  IMPORTED = 5
}

export class ScanResult {
  kind: ScanResultKind = ScanResultKind.CANCELLED;
  parsed: ParsedOtpAuth | null = null;
  importedCount: number = 0;
}

// 申请相机权限并拉起系统扫码，解析结果交给调用方处理
export async function scanQrCode(ctx: common.UIAbilityContext): Promise<ScanResult> {
  const result = new ScanResult();
  try {
    const atManager = abilityAccessCtrl.createAtManager();
    const perms: Permissions[] = ['ohos.permission.CAMERA'];
    const r: PermissionRequestResult = await atManager.requestPermissionsFromUser(ctx, perms);
    const granted = r.authResults && r.authResults[0] === 0;
    if (!granted) {
      result.kind = ScanResultKind.PERMISSION_DENIED;
      return result;
    }
  } catch (e) {
    console.error('[ScanService.permission]', e);
    result.kind = ScanResultKind.PERMISSION_DENIED;
    return result;
  }

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
        await SecretVault.put(acct.id, item.secret);
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
