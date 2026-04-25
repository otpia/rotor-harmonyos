import { describe, it, expect } from '@ohos/hypium';
import { parseOtpAuth } from '../../../../main/ets/utils/OtpAuthUri';
import { OtpType } from '../../../../main/ets/model/OtpAccount';

export default function otpAuthUriTests() {
  describe('OtpAuthUri', () => {
    it('parses canonical TOTP', 0, () => {
      const r = parseOtpAuth('otpauth://totp/Google:alice@example.com?secret=JBSWY3DPEHPK3PXP&issuer=Google&period=30&digits=6&algorithm=SHA1');
      expect(r.name).assertEqual('Google');
      expect(r.note).assertEqual('alice@example.com');
      expect(r.secret).assertEqual('JBSWY3DPEHPK3PXP');
      expect(r.account.type).assertEqual(OtpType.TOTP);
      expect(r.account.period).assertEqual(30);
      expect(r.account.digits).assertEqual(6);
    });

    it('parses with only label and no issuer query', 0, () => {
      const r = parseOtpAuth('otpauth://totp/alice@example.com?secret=JBSWY3DPEHPK3PXP');
      expect(r.name).assertEqual('alice@example.com');
      expect(r.note).assertEqual('');
    });

    it('handles URL-encoded label and issuer', 0, () => {
      const r = parseOtpAuth('otpauth://totp/My%20Issuer:user%40x.com?secret=ABCDEFGH&issuer=My%20Issuer');
      expect(r.name).assertEqual('My Issuer');
      expect(r.note).assertEqual('user@x.com');
    });

    it('rejects non otpauth scheme', 0, () => {
      let threw = false;
      try { parseOtpAuth('https://example.com'); } catch (_e) { threw = true; }
      expect(threw).assertTrue();
    });
  });
}
