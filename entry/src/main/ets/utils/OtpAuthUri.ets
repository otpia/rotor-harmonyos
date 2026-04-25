import { OtpAccount, OtpType, defaultAccount } from '../model/OtpAccount';

export interface ParsedOtpAuth {
  name: string;
  note: string;
  secret: string;
  account: OtpAccount;
}

export function parseOtpAuth(uri: string): ParsedOtpAuth {
  if (!uri.startsWith('otpauth://')) {
    throw new Error('not an otpauth uri');
  }
  const rest = uri.substring('otpauth://'.length);
  const slash = rest.indexOf('/');
  if (slash < 0) {
    throw new Error('missing type segment');
  }
  const typeStr = rest.substring(0, slash).toLowerCase();
  const tail = rest.substring(slash + 1);
  const qmark = tail.indexOf('?');
  const labelEnc = qmark >= 0 ? tail.substring(0, qmark) : tail;
  const queryStr = qmark >= 0 ? tail.substring(qmark + 1) : '';
  const label = decodeURIComponent(labelEnc);
  const params = parseQuery(queryStr);

  let name = '';
  let note = '';
  const colon = label.indexOf(':');
  if (colon >= 0) {
    name = label.substring(0, colon).trim();
    note = label.substring(colon + 1).trim();
  } else {
    name = label.trim();
  }
  const issuer = params['issuer'];
  if (issuer && issuer.length > 0) {
    name = issuer;
  }

  const acct = defaultAccount();
  acct.type = typeStr === 'hotp' ? OtpType.HOTP : OtpType.TOTP;
  acct.name = name;
  acct.note = note;
  acct.period = params['period'] ? parseInt(params['period']) : 30;
  acct.digits = params['digits'] ? parseInt(params['digits']) : 6;
  const algo = (params['algorithm'] || 'SHA1').toUpperCase();
  acct.algorithm = (algo === 'SHA256' || algo === 'SHA512') ? (algo as ('SHA256' | 'SHA512')) : 'SHA1';
  acct.counter = params['counter'] ? parseInt(params['counter']) : 0;

  const secret = params['secret'] || '';
  return { name, note, secret, account: acct };
}

function parseQuery(q: string): Record<string, string> {
  const out: Record<string, string> = {};
  if (!q) return out;
  for (const part of q.split('&')) {
    if (!part) continue;
    const eq = part.indexOf('=');
    const k = eq >= 0 ? part.substring(0, eq) : part;
    const v = eq >= 0 ? part.substring(eq + 1) : '';
    out[decodeURIComponent(k)] = decodeURIComponent(v);
  }
  return out;
}
