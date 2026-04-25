import { cryptoFramework } from '@kit.CryptoArchitectureKit';

// 计算 HMAC，algo 取值 SHA1/SHA256/SHA512
export async function hmac(algo: string, key: Uint8Array, message: Uint8Array): Promise<Uint8Array> {
  try {
    const mac = cryptoFramework.createMac(`HMAC|${algo}`);
    const symKeyGen = cryptoFramework.createSymKeyGenerator(`HMAC|${algo}`);
    const keyBlob: cryptoFramework.DataBlob = { data: key };
    const symKey = await symKeyGen.convertKey(keyBlob);
    await mac.init(symKey);
    await mac.update({ data: message } as cryptoFramework.DataBlob);
    const result = await mac.doFinal();
    return new Uint8Array(result.data);
  } catch (e) {
    console.error('[HmacSha1.hmac]', e);
    throw new Error('hmac failed');
  }
}

// 把 64 位整数（毫秒级 / 计数器）编码为 8 字节大端
export function uint64ToBytesBE(value: number): Uint8Array {
  const out = new Uint8Array(8);
  let hi = Math.floor(value / 0x100000000);
  let lo = value >>> 0;
  out[0] = (hi >>> 24) & 0xff;
  out[1] = (hi >>> 16) & 0xff;
  out[2] = (hi >>> 8) & 0xff;
  out[3] = hi & 0xff;
  out[4] = (lo >>> 24) & 0xff;
  out[5] = (lo >>> 16) & 0xff;
  out[6] = (lo >>> 8) & 0xff;
  out[7] = lo & 0xff;
  return out;
}
