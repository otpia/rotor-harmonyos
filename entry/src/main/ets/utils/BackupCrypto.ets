import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { hmac } from './HmacSha1';

const ITER = 200000;
const SALT_BYTES = 16;
const IV_BYTES = 16;
const ENC_KEY_BYTES = 32;
const MAC_KEY_BYTES = 32;

export interface BackupFile {
  version: number;
  kdf: string;
  iter: number;
  salt: string;
  iv: string;
  ciphertext: string;
  mac: string;
}

interface DerivedKeys {
  encKey: Uint8Array;
  macKey: Uint8Array;
}

function utf8(s: string): Uint8Array {
  return new util.TextEncoder('utf-8').encodeInto(s);
}

function utf8Decode(buf: Uint8Array): string {
  return util.TextDecoder.create('utf-8').decodeToString(buf);
}

function b64Encode(bytes: Uint8Array): string {
  return new util.Base64Helper().encodeToStringSync(bytes);
}

function b64Decode(s: string): Uint8Array {
  return new util.Base64Helper().decodeSync(s);
}

function randomBytes(n: number): Uint8Array {
  const r = cryptoFramework.createRandom();
  const blob = r.generateRandomSync(n);
  return new Uint8Array(blob.data);
}

function concat(a: Uint8Array, b: Uint8Array): Uint8Array {
  const out = new Uint8Array(a.length + b.length);
  out.set(a, 0);
  out.set(b, a.length);
  return out;
}

async function deriveKeys(password: string, salt: Uint8Array): Promise<DerivedKeys> {
  const kdf = cryptoFramework.createKdf('PBKDF2|SHA256');
  const spec: cryptoFramework.PBKDF2Spec = {
    algName: 'PBKDF2',
    password: password,
    salt: salt,
    iterations: ITER,
    keySize: ENC_KEY_BYTES + MAC_KEY_BYTES
  };
  const blob = await kdf.generateSecret(spec);
  const out = new Uint8Array(blob.data);
  return {
    encKey: out.slice(0, ENC_KEY_BYTES),
    macKey: out.slice(ENC_KEY_BYTES, ENC_KEY_BYTES + MAC_KEY_BYTES)
  };
}

async function aesCbc(mode: cryptoFramework.CryptoMode, key: Uint8Array, iv: Uint8Array, input: Uint8Array): Promise<Uint8Array> {
  const gen = cryptoFramework.createSymKeyGenerator('AES256');
  const symKey = await gen.convertKey({ data: key } as cryptoFramework.DataBlob);
  const cipher = cryptoFramework.createCipher('AES256|CBC|PKCS7');
  const params: cryptoFramework.IvParamsSpec = {
    algName: 'IvParamsSpec',
    iv: { data: iv } as cryptoFramework.DataBlob
  };
  await cipher.init(mode, symKey, params);
  const update = await cipher.update({ data: input } as cryptoFramework.DataBlob);
  const doFinal = await cipher.doFinal(null);
  const left = update && update.data ? new Uint8Array(update.data) : new Uint8Array(0);
  const right = doFinal && doFinal.data ? new Uint8Array(doFinal.data) : new Uint8Array(0);
  return concat(left, right);
}

export async function encryptBackup(password: string, plaintext: string): Promise<BackupFile> {
  const salt = randomBytes(SALT_BYTES);
  const iv = randomBytes(IV_BYTES);
  const keys = await deriveKeys(password, salt);
  const ct = await aesCbc(cryptoFramework.CryptoMode.ENCRYPT_MODE, keys.encKey, iv, utf8(plaintext));
  const macInput = concat(concat(iv, salt), ct);
  const tag = await hmac('SHA256', keys.macKey, macInput);
  return {
    version: 1,
    kdf: 'pbkdf2-sha256',
    iter: ITER,
    salt: b64Encode(salt),
    iv: b64Encode(iv),
    ciphertext: b64Encode(ct),
    mac: b64Encode(tag)
  };
}

function constantTimeEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}

export async function decryptBackup(password: string, file: BackupFile): Promise<string> {
  if (file.version !== 1) throw new Error('unsupported version');
  const salt = b64Decode(file.salt);
  const iv = b64Decode(file.iv);
  const ct = b64Decode(file.ciphertext);
  const expectedMac = b64Decode(file.mac);
  const keys = await deriveKeys(password, salt);
  const macInput = concat(concat(iv, salt), ct);
  const tag = await hmac('SHA256', keys.macKey, macInput);
  if (!constantTimeEqual(tag, expectedMac)) throw new Error('mac mismatch');
  const pt = await aesCbc(cryptoFramework.CryptoMode.DECRYPT_MODE, keys.encKey, iv, ct);
  return utf8Decode(pt);
}
