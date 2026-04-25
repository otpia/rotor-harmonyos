const ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

export function base32Normalize(input: string): string {
  return input.replace(/[\s-]/g, '').toUpperCase().replace(/=+$/, '');
}

export function base32Decode(input: string): Uint8Array {
  const norm = base32Normalize(input);
  if (norm.length === 0) {
    return new Uint8Array(0);
  }
  const out: number[] = [];
  let buffer = 0;
  let bits = 0;
  for (let i = 0; i < norm.length; i++) {
    const ch = norm.charAt(i);
    const idx = ALPHABET.indexOf(ch);
    if (idx < 0) {
      throw new Error(`invalid base32 character: ${ch}`);
    }
    buffer = (buffer << 5) | idx;
    bits += 5;
    if (bits >= 8) {
      bits -= 8;
      out.push((buffer >> bits) & 0xff);
    }
  }
  return new Uint8Array(out);
}

export function isValidBase32(input: string): boolean {
  try {
    return base32Decode(input).length > 0;
  } catch (_e) {
    return false;
  }
}
