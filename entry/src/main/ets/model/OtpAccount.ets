// 账号类型枚举（MVP 仅使用 TOTP）
export enum OtpType {
  TOTP = 'totp',
  HOTP = 'hotp'
}

// 账号数据，secret 为 base32 密钥
export interface OtpAccount {
  id: string;
  name: string;
  note: string;
  type: OtpType;
  period: number;
  digits: number;
  algorithm: 'SHA1' | 'SHA256' | 'SHA512';
  counter: number;
  iconKey: string;
  orderIndex: number;
  createdAt: number;
  updatedAt: number;
  secret: string;
}

export function defaultAccount(): OtpAccount {
  const now = Date.now();
  return {
    id: '',
    name: '',
    note: '',
    type: OtpType.TOTP,
    period: 30,
    digits: 6,
    algorithm: 'SHA1',
    counter: 0,
    iconKey: '',
    orderIndex: 0,
    createdAt: now,
    updatedAt: now,
    secret: ''
  };
}

// 浅拷贝一份账号，供编辑页修改，避免直接改动列表中的对象
export function cloneAccount(a: OtpAccount): OtpAccount {
  return {
    id: a.id,
    name: a.name,
    note: a.note,
    type: a.type,
    period: a.period,
    digits: a.digits,
    algorithm: a.algorithm,
    counter: a.counter,
    iconKey: a.iconKey,
    orderIndex: a.orderIndex,
    createdAt: a.createdAt,
    updatedAt: a.updatedAt,
    secret: a.secret
  };
}
