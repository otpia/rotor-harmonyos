import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';

const ALIAS_PREFIX = 'otp_secret_';

function aliasFor(id: string): string {
  return ALIAS_PREFIX + id;
}

function strToUint8(s: string): Uint8Array {
  const enc = new util.TextEncoder('utf-8');
  return enc.encodeInto(s);
}

function uint8ToStr(buf: Uint8Array): string {
  const dec = util.TextDecoder.create('utf-8');
  return dec.decodeToString(buf);
}

export class SecretVault {
  static async put(id: string, secretBase32: string): Promise<void> {
    const attr: asset.AssetMap = new Map();
    attr.set(asset.Tag.SECRET, strToUint8(secretBase32));
    attr.set(asset.Tag.ALIAS, strToUint8(aliasFor(id)));
    attr.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
    try {
      await asset.add(attr);
    } catch (_e) {
      await SecretVault.update(id, secretBase32);
    }
  }

  static async update(id: string, secretBase32: string): Promise<void> {
    const query: asset.AssetMap = new Map();
    query.set(asset.Tag.ALIAS, strToUint8(aliasFor(id)));
    const upd: asset.AssetMap = new Map();
    upd.set(asset.Tag.SECRET, strToUint8(secretBase32));
    await asset.update(query, upd);
  }

  static async get(id: string): Promise<string> {
    const query: asset.AssetMap = new Map();
    query.set(asset.Tag.ALIAS, strToUint8(aliasFor(id)));
    query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
    const arr = await asset.query(query);
    if (arr.length === 0) {
      throw new Error('secret not found: ' + id);
    }
    const sec = arr[0].get(asset.Tag.SECRET) as Uint8Array;
    return uint8ToStr(sec);
  }

  static async remove(id: string): Promise<void> {
    const query: asset.AssetMap = new Map();
    query.set(asset.Tag.ALIAS, strToUint8(aliasFor(id)));
    try {
      await asset.remove(query);
    } catch (_e) {
      // 不存在则忽略
    }
  }
}
