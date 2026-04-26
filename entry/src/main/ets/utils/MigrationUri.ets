import { util } from '@kit.ArkTS';
import { OtpType, defaultAccount } from '../model/OtpAccount';
import { ParsedOtpAuth } from './OtpAuthUri';
import { base32Encode } from './Base32';

// 轻量 protobuf 解析器：仅识别 varint 与 length-delimited，足以解析 Google Authenticator 转移协议
interface ProtoField {
  fieldNumber: number;
  wireType: number;
  varint: number;
  bytes: Uint8Array;
}

class ProtoReader {
  private buf: Uint8Array;
  private pos: number = 0;

  constructor(buf: Uint8Array) {
    this.buf = buf;
  }

  hasMore(): boolean {
    return this.pos < this.buf.length;
  }

  private readVarint(): number {
    let v = 0;
    let shift = 0;
    while (this.pos < this.buf.length) {
      const b = this.buf[this.pos++];
      v |= (b & 0x7f) << shift;
      if ((b & 0x80) === 0) return v >>> 0;
      shift += 7;
      if (shift >= 32) {
        // 超过 32 位，跳过剩余字节但不再累加（counter 实际不会这么大）
        while (this.pos < this.buf.length && (this.buf[this.pos++] & 0x80) !== 0) {
        }
        return v >>> 0;
      }
    }
    return v >>> 0;
  }

  next(): ProtoField {
    const tag = this.readVarint();
    const fieldNumber = tag >>> 3;
    const wireType = tag & 0x7;
    let varint = 0;
    let bytes = new Uint8Array(0);
    if (wireType === 0) {
      varint = this.readVarint();
    } else if (wireType === 2) {
      const len = this.readVarint();
      bytes = this.buf.slice(this.pos, this.pos + len);
      this.pos += len;
    } else if (wireType === 1) {
      this.pos += 8;
    } else if (wireType === 5) {
      this.pos += 4;
    }
    return { fieldNumber, wireType, varint, bytes };
  }
}

function bytesToUtf8(buf: Uint8Array): string {
  const dec = util.TextDecoder.create('utf-8');
  return dec.decodeToString(buf);
}

function parseOtpParameters(buf: Uint8Array): ParsedOtpAuth {
  let secretBytes = new Uint8Array(0);
  let rawName = '';
  let issuer = '';
  let algoEnum = 1;
  let digitsEnum = 1;
  let typeEnum = 2;
  let counter = 0;

  const reader = new ProtoReader(buf);
  while (reader.hasMore()) {
    const f = reader.next();
    if (f.fieldNumber === 1 && f.wireType === 2) secretBytes = f.bytes;
    else if (f.fieldNumber === 2 && f.wireType === 2) rawName = bytesToUtf8(f.bytes);
    else if (f.fieldNumber === 3 && f.wireType === 2) issuer = bytesToUtf8(f.bytes);
    else if (f.fieldNumber === 4 && f.wireType === 0) algoEnum = f.varint;
    else if (f.fieldNumber === 5 && f.wireType === 0) digitsEnum = f.varint;
    else if (f.fieldNumber === 6 && f.wireType === 0) typeEnum = f.varint;
    else if (f.fieldNumber === 7 && f.wireType === 0) counter = f.varint;
  }

  const acct = defaultAccount();
  acct.type = typeEnum === 1 ? OtpType.HOTP : OtpType.TOTP;
  acct.digits = digitsEnum === 2 ? 8 : 6;
  acct.algorithm = algoEnum === 2 ? 'SHA256' : (algoEnum === 3 ? 'SHA512' : 'SHA1');
  acct.counter = counter;
  acct.period = 30;

  // label 可能是 "Issuer:user" 也可能仅 "user"，issuer 字段优先作为 name
  let displayName = issuer.trim();
  let note = '';
  const colon = rawName.indexOf(':');
  if (colon >= 0) {
    const left = rawName.substring(0, colon).trim();
    const right = rawName.substring(colon + 1).trim();
    if (!displayName) displayName = left;
    note = right;
  } else {
    const t = rawName.trim();
    if (!displayName) displayName = t;
    else note = t;
  }

  return {
    name: displayName,
    note,
    secret: base32Encode(secretBytes),
    account: acct
  };
}

export function isMigrationUri(uri: string): boolean {
  return uri.startsWith('otpauth-migration://offline?');
}

export function parseMigrationUri(uri: string): ParsedOtpAuth[] {
  const PREFIX = 'otpauth-migration://offline?';
  if (!uri.startsWith(PREFIX)) {
    throw new Error('not a migration uri');
  }
  const queryStr = uri.substring(PREFIX.length);
  let dataEnc = '';
  for (const part of queryStr.split('&')) {
    const eq = part.indexOf('=');
    const k = eq >= 0 ? part.substring(0, eq) : part;
    if (k === 'data') {
      dataEnc = eq >= 0 ? part.substring(eq + 1) : '';
      break;
    }
  }
  if (!dataEnc) throw new Error('missing data param');
  const b64 = decodeURIComponent(dataEnc);
  const helper = new util.Base64Helper();
  const payload = helper.decodeSync(b64);

  const out: ParsedOtpAuth[] = [];
  const reader = new ProtoReader(payload);
  while (reader.hasMore()) {
    const f = reader.next();
    if (f.fieldNumber === 1 && f.wireType === 2) {
      try {
        const item = parseOtpParameters(f.bytes);
        if (item.secret) out.push(item);
      } catch (e) {
        console.error('[parseMigrationUri.entry]', e);
      }
    }
  }
  return out;
}
