import { describe, it, expect } from '@ohos/hypium';
import { base32Decode, base32Normalize } from '../../../../main/ets/utils/Base32';

export default function base32Tests() {
  describe('Base32', () => {
    it('decodes RFC 4648 vectors', 0, () => {
      const cases: [string, number[]][] = [
        ['', []],
        ['MY======', [0x66]],
        ['MZXQ====', [0x66, 0x6f]],
        ['MZXW6===', [0x66, 0x6f, 0x6f]],
        ['MZXW6YQ=', [0x66, 0x6f, 0x6f, 0x62]],
        ['MZXW6YTB', [0x66, 0x6f, 0x6f, 0x62, 0x61]],
        ['MZXW6YTBOI======', [0x66, 0x6f, 0x6f, 0x62, 0x61, 0x72]]
      ];
      for (const c of cases) {
        const out = Array.from(base32Decode(c[0]));
        expect(out.length).assertEqual(c[1].length);
        for (let i = 0; i < out.length; i++) {
          expect(out[i]).assertEqual(c[1][i]);
        }
      }
    });

    it('tolerates lowercase, spaces and dashes', 0, () => {
      const a = Array.from(base32Decode('jbsw y3dp'));
      const b = Array.from(base32Decode('JBSWY3DP'));
      expect(a.length).assertEqual(b.length);
      for (let i = 0; i < a.length; i++) {
        expect(a[i]).assertEqual(b[i]);
      }
    });

    it('rejects illegal characters', 0, () => {
      let threw = false;
      try { base32Decode('!!!'); } catch (e) { threw = true; }
      expect(threw).assertTrue();
    });

    it('normalizes input', 0, () => {
      expect(base32Normalize(' jb-sw y3 dp ')).assertEqual('JBSWY3DP');
    });
  });
}
