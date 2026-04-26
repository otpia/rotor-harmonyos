import { common } from '@kit.AbilityKit';
import { OtpAccountStore } from './OtpAccountStore';
import { SecretVault } from './SecretVault';

export async function existingSecretSet(ctx: common.UIAbilityContext): Promise<Set<string>> {
  const accounts = await OtpAccountStore.listAll(ctx);
  const set = new Set<string>();
  for (const a of accounts) {
    try {
      const sec = await SecretVault.get(a.id);
      if (sec) set.add(sec);
    } catch (e) {
      console.error('[existingSecretSet]', e);
    }
  }
  return set;
}
