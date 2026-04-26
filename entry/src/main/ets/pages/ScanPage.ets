import { scanCore, scanBarcode } from '@kit.ScanKit';
import { abilityAccessCtrl, common, PermissionRequestResult, Permissions } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { parseOtpAuth, ParsedOtpAuth } from '../utils/OtpAuthUri';
import { isMigrationUri, parseMigrationUri } from '../utils/MigrationUri';
import { OtpAccountStore } from '../services/OtpAccountStore';
import { SecretVault } from '../services/SecretVault';
import { PageContainer } from '../components/PageContainer';

@Entry
@Component
struct ScanPage {
  aboutToAppear(): void {
    this.requestAndScan();
  }

  private async requestAndScan(): Promise<void> {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const atManager = abilityAccessCtrl.createAtManager();
    const perms: Permissions[] = ['ohos.permission.CAMERA'];
    try {
      const r: PermissionRequestResult = await atManager.requestPermissionsFromUser(ctx, perms);
      const granted = r.authResults && r.authResults[0] === 0;
      if (!granted) {
        this.getUIContext().getPromptAction().showToast({ message: '需要相机权限' });
        this.getUIContext().getRouter().back();
        return;
      }
      const opts: scanBarcode.ScanOptions = {
        scanTypes: [scanCore.ScanType.QR_CODE],
        enableMultiMode: false,
        enableAlbum: true
      };
      const result = await scanBarcode.startScanForResult(ctx, opts);
      const text = result.originalValue || '';
      if (isMigrationUri(text)) {
        await this.importMigration(ctx, text);
        return;
      }
      try {
        const parsed: ParsedOtpAuth = parseOtpAuth(text);
        this.getUIContext().getRouter().replaceUrl({
          url: 'pages/EditPage',
          params: { prefilled: parsed.account, prefilledSecret: parsed.secret }
        });
      } catch (_e) {
        this.getUIContext().getPromptAction().showToast({ message: '未识别的二维码' });
        this.getUIContext().getRouter().back();
      }
    } catch (_e) {
      this.getUIContext().getRouter().back();
    }
  }

  private async importMigration(ctx: common.UIAbilityContext, uri: string): Promise<void> {
    let items: ParsedOtpAuth[] = [];
    try {
      items = parseMigrationUri(uri);
    } catch (e) {
      console.error('[ScanPage.importMigration] parse failed', e);
      this.getUIContext().getPromptAction().showToast({ message: '未识别的二维码' });
      this.getUIContext().getRouter().back();
      return;
    }
    if (items.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '二维码中没有可导入的账号' });
      this.getUIContext().getRouter().back();
      return;
    }
    let imported = 0;
    let order = await OtpAccountStore.maxOrderIndex(ctx);
    for (const item of items) {
      try {
        const acct = item.account;
        acct.id = util.generateRandomUUID(false);
        acct.name = item.name;
        acct.note = item.note;
        order += 1;
        acct.orderIndex = order;
        const now = Date.now();
        acct.createdAt = now;
        acct.updatedAt = now;
        await SecretVault.put(acct.id, item.secret);
        await OtpAccountStore.insert(ctx, acct);
        imported += 1;
      } catch (e) {
        console.error('[ScanPage.importMigration] insert failed', e);
      }
    }
    this.getUIContext().getPromptAction().showToast({ message: `已导入 ${imported} 个账号` });
    this.getUIContext().getRouter().back();
  }

  @Builder PageBody() {
    Column() {
      Text('正在打开相机…').fontColor($r('app.color.text_primary'))
    }.width('100%').height('100%').justifyContent(FlexAlign.Center)
  }

  build() {
    Stack() {
      PageContainer({ content: () => { this.PageBody() } })
    }.width('100%').height('100%')
  }
}
