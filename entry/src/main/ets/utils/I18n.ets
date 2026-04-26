import { common } from '@kit.AbilityKit';

// 包装 resourceManager.getStringByNameSync，吞掉异常并返回名字本身做兜底
export function getString(ctx: common.UIAbilityContext, name: string, ...args: Array<string | number>): string {
  try {
    return ctx.resourceManager.getStringByNameSync(name, ...args);
  } catch (e) {
    console.error('[i18n.getString]', name, e);
    return name;
  }
}
