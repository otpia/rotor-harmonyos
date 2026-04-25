import { describe, it, expect } from '@ohos/hypium';
import { totp, formatGroups } from '../../../../main/ets/services/OtpEngine';

const SECRET = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';

export default function otpEngineTests() {
  describe('OtpEngine', () => {
    it('matches RFC 6238 vector at T=59', 0, async () => {
      const code = await totp(SECRET, 59 * 1000, 30, 8, 'SHA1');
      expect(code).assertEqual('94287082');
    });

    it('matches RFC 6238 vector at T=1111111109', 0, async () => {
      const code = await totp(SECRET, 1111111109 * 1000, 30, 8, 'SHA1');
      expect(code).assertEqual('07081804');
    });

    it('truncates to 6 digits with leading zeros', 0, async () => {
      const code = await totp(SECRET, 59 * 1000, 30, 6, 'SHA1');
      expect(code.length).assertEqual(6);
    });

    it('formatGroups inserts middle space for 6 digits', 0, () => {
      expect(formatGroups('123456')).assertEqual('123 456');
    });
  });
}
