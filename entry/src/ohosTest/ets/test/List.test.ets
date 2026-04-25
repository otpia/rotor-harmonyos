import abilityTest from './Ability.test';
import base32Tests from './Base32.test';
import otpEngineTests from './OtpEngine.test';

export default function testsuite() {
  abilityTest();
  base32Tests();
  otpEngineTests();
}