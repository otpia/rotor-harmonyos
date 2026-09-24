import { common } from '@kit.AbilityKit';
import { OtpAccountStore } from './OtpAccountStore';

export async function existingSecretSet(ctx: common.UIAbilityContext): Promise<Set<string>> {
  const accounts = await OtpAccountStore.listAll(ctx);
  const set = new Set<string>();
  for (const a of accounts) {
    if (a.secret) {
      set.add(a.secret);
    }
  }
  return set;
}
