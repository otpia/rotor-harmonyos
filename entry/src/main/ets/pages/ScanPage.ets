import { scanCore, scanBarcode } from '@kit.ScanKit';
import { abilityAccessCtrl, common, PermissionRequestResult, Permissions } from '@kit.AbilityKit';
import { parseOtpAuth, ParsedOtpAuth } from '../utils/OtpAuthUri';

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

  build() {
    Column() {
      Text('正在打开相机…').fontColor($r('app.color.text_primary'))
    }.width('100%').height('100%').justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.bg_app'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
