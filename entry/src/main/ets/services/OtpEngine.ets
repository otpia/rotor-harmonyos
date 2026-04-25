import { base32Decode } from '../utils/Base32';
import { hmac, uint64ToBytesBE } from '../utils/HmacSha1';

export async function totp(
  secretBase32: string,
  nowMs: number,
  period: number,
  digits: number,
  algorithm: 'SHA1' | 'SHA256' | 'SHA512'
): Promise<string> {
  const t = Math.floor(nowMs / 1000 / period);
  const msg = uint64ToBytesBE(t);
  const key = base32Decode(secretBase32);
  const mac = await hmac(algorithm, key, msg);
  const offset = mac[mac.length - 1] & 0x0f;
  const bin = ((mac[offset] & 0x7f) << 24) |
              ((mac[offset + 1] & 0xff) << 16) |
              ((mac[offset + 2] & 0xff) << 8) |
              (mac[offset + 3] & 0xff);
  const mod = Math.pow(10, digits);
  const code = (bin % mod).toString().padStart(digits, '0');
  return code;
}

export async function hotp(
  secretBase32: string,
  counter: number,
  digits: number,
  algorithm: 'SHA1' | 'SHA256' | 'SHA512'
): Promise<string> {
  const msg = uint64ToBytesBE(counter);
  const key = base32Decode(secretBase32);
  const mac = await hmac(algorithm, key, msg);
  const offset = mac[mac.length - 1] & 0x0f;
  const bin = ((mac[offset] & 0x7f) << 24) |
              ((mac[offset + 1] & 0xff) << 16) |
              ((mac[offset + 2] & 0xff) << 8) |
              (mac[offset + 3] & 0xff);
  const mod = Math.pow(10, digits);
  return (bin % mod).toString().padStart(digits, '0');
}

export function formatGroups(code: string): string {
  if (code.length === 6) {
    return `${code.slice(0, 3)} ${code.slice(3)}`;
  }
  if (code.length === 8) {
    return `${code.slice(0, 4)} ${code.slice(4)}`;
  }
  return code;
}

export function remainingSeconds(nowMs: number, period: number): number {
  return period - Math.floor(nowMs / 1000) % period;
}
