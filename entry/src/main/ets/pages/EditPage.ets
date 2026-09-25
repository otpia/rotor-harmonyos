import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { uiMaterial } from '@kit.ArkUI';
import { HdsNavDestination, hdsMaterial, ScrollEffectType } from '@kit.UIDesignKit';
import { OtpAccount, OtpType, cloneAccount, defaultAccount } from '../model/OtpAccount';
import { OtpAccountStore } from '../services/OtpAccountStore';
import { isValidBase32, base32Normalize } from '../utils/Base32';
import { getString } from '../utils/I18n';
import { IssuerAvatar } from '../components/IssuerAvatar';
import { IconPicker } from '../components/IconPicker';

export interface EditParams {
  id?: string;
  prefilled?: OtpAccount;
  prefilledSecret?: string;
}

const PERIODS: number[] = [15, 30, 60];
const DIGITS: number[] = [6, 8];
const ALGORITHMS: string[] = ['SHA1', 'SHA256', 'SHA512'];
const LABEL_WIDTH = 64;
const ROW_HEIGHT = 56;

@Component
export struct EditPage {
  params: EditParams = {};
  @Consume('pathStack') pathStack: NavPathStack;
  @State account: OtpAccount = defaultAccount();
  @State secret: string = '';
  @State isEdit: boolean = false;
  @State advancedOpen: boolean = false;
  @State iconSheetOpen: boolean = false;
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    const p = this.params;
    if (p.id) {
      this.isEdit = true;
      if (p.prefilled) {
        this.account = cloneAccount(p.prefilled);
        this.secret = p.prefilled.secret;
      }
    } else if (p.prefilled) {
      this.account = cloneAccount(p.prefilled);
      this.secret = p.prefilledSecret || '';
    }
  }

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private toast(msg: ResourceStr): void {
    try {
      this.getUIContext().getPromptAction().showToast({
        message: msg,
        systemMaterial: new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.THICK })
      });
    } catch (e) {
      console.error('[EditPage.toast]', e);
    }
  }

  private async save(): Promise<void> {
    try {
      if (this.account.name.length === 0) {
        this.toast($r('app.string.name_required'));
        return;
      }
      if (!isValidBase32(this.secret)) {
        this.toast($r('app.string.secret_invalid'));
        return;
      }
      const ctx = this.ctx();
      const now = Date.now();
      if (!this.isEdit) {
        this.account.id = util.generateRandomUUID(false);
        this.account.createdAt = now;
        this.account.orderIndex = (await OtpAccountStore.maxOrderIndex(ctx)) + 1;
      }
      this.account.updatedAt = now;
      this.account.secret = base32Normalize(this.secret);
      if (this.isEdit) {
        await OtpAccountStore.update(ctx, this.account);
      } else {
        await OtpAccountStore.insert(ctx, this.account);
      }
      this.pathStack.pop();
    } catch (e) {
      console.error('[EditPage.save]', e);
    }
  }

  // ---------- 下拉选项 ----------

  private typeOptions(): SelectOption[] {
    const out: SelectOption[] = [];
    out.push({ value: $r('app.string.type_totp') });
    out.push({ value: $r('app.string.type_hotp') });
    return out;
  }

  private periodOptions(): SelectOption[] {
    const ctx = this.ctx();
    const out: SelectOption[] = [];
    for (const p of PERIODS) {
      out.push({ value: getString(ctx, 'period_seconds', p) });
    }
    return out;
  }

  private digitsOptions(): SelectOption[] {
    const ctx = this.ctx();
    const out: SelectOption[] = [];
    for (const d of DIGITS) {
      out.push({ value: getString(ctx, 'digits_count', d) });
    }
    return out;
  }

  private algorithmOptions(): SelectOption[] {
    const out: SelectOption[] = [];
    for (const a of ALGORITHMS) {
      out.push({ value: a });
    }
    return out;
  }

  private setAlgorithm(index: number): void {
    if (index === 1) {
      this.account.algorithm = 'SHA256';
    } else if (index === 2) {
      this.account.algorithm = 'SHA512';
    } else {
      this.account.algorithm = 'SHA1';
    }
  }

  private indexOrZero(list: number[], v: number): number {
    const i = list.indexOf(v);
    return i < 0 ? 0 : i;
  }

  // ---------- 行构建器 ----------

  @Styles cardStyle() {
    .backgroundColor($r('sys.color.comp_background_list_card'))
    .borderRadius($r('sys.float.corner_radius_level8'))
    .width('100%')
  }

  @Builder InputRow(label: Resource, value: string, inputType: InputType, onChange: (v: string) => void) {
    Row() {
      Text(label)
        .fontSize($r('sys.float.Body_L'))
        .fontColor($r('sys.color.font_primary'))
        .width(LABEL_WIDTH)
      TextInput({ text: value })
        .type(inputType)
        .fontSize($r('sys.float.Body_L'))
        .backgroundColor(Color.Transparent)
        .padding({ left: 0, right: 0 })
        .height(40)
        .layoutWeight(1)
        .onChange(onChange)
    }
    .width('100%')
    .height(ROW_HEIGHT)
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder SelectRow(label: Resource, options: SelectOption[], selectedIndex: number, valueText: ResourceStr,
    onSelect: (i: number) => void) {
    Row() {
      Text(label)
        .fontSize($r('sys.float.Body_L'))
        .fontColor($r('sys.color.font_primary'))
        .layoutWeight(1)
      Select(options)
        .selected(selectedIndex)
        .value(valueText)
        .font({ size: $r('sys.float.Body_L') })
        .fontColor($r('sys.color.font_secondary'))
        .onSelect((i: number) => {
          onSelect(i);
        })
    }
    .width('100%')
    .height(ROW_HEIGHT)
    .padding({ left: 16, right: 8 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder IconSheet() {
    IconPicker({
      current: this.account.iconKey,
      onPick: (iconKey: string) => {
        this.account.iconKey = iconKey;
        this.iconSheetOpen = false;
      }
    })
  }

  @Builder RowDivider(indent: number) {
    Divider()
      .color($r('sys.color.comp_divider'))
      .strokeWidth(0.5)
      .margin({ left: indent, right: 16 })
  }

  build() {
    HdsNavDestination() {
      Scroll(this.scroller) {
        Column({ space: 12 }) {
          Column({ space: 4 }) {
            IssuerAvatar({ name: this.account.name, iconKey: this.account.iconKey, diameter: 72 })
              .onClick(() => {
                this.iconSheetOpen = true;
              })
            Button($r('app.string.icon_change'))
              .buttonStyle(ButtonStyleMode.TEXTUAL)
              .controlSize(ControlSize.NORMAL)
              .responseRegion({ x: 0, y: -4, width: '100%', height: 48 })
              .onClick(() => {
                this.iconSheetOpen = true;
              })
          }
          .margin({ top: 12 })

          Column() {
            this.InputRow($r('app.string.label_name'), this.account.name, InputType.Normal, (v: string) => {
              this.account.name = v;
            })
            this.RowDivider(16 + LABEL_WIDTH)
            this.InputRow($r('app.string.label_note'), this.account.note, InputType.Normal, (v: string) => {
              this.account.note = v;
            })
          }
          .cardStyle()

          Column() {
            this.InputRow($r('app.string.label_secret'), this.secret, InputType.Normal, (v: string) => {
              this.secret = v;
            })
          }
          .cardStyle()

          Column() {
            this.SelectRow($r('app.string.label_type'), this.typeOptions(),
              this.account.type === OtpType.TOTP ? 0 : 1,
              this.account.type === OtpType.TOTP ? $r('app.string.type_totp') : $r('app.string.type_hotp'),
              (i: number) => {
                this.account.type = i === 1 ? OtpType.HOTP : OtpType.TOTP;
              })
            if (this.account.type === OtpType.HOTP) {
              this.RowDivider(16)
              this.InputRow($r('app.string.label_counter'), String(this.account.counter), InputType.Number,
                (v: string) => {
                  const n = parseInt(v);
                  this.account.counter = isNaN(n) ? 0 : n;
                })
            }
          }
          .cardStyle()

          Column() {
            Row() {
              Text($r('app.string.advanced_options'))
                .fontSize($r('sys.float.Body_L'))
                .fontColor($r('sys.color.font_primary'))
                .layoutWeight(1)
              SymbolGlyph(this.advancedOpen ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
                .fontSize(20)
                .fontColor([$r('sys.color.icon_secondary')])
            }
            .width('100%')
            .height(ROW_HEIGHT)
            .padding({ left: 16, right: 16 })
            .alignItems(VerticalAlign.Center)
            .onClick(() => {
              this.getUIContext().animateTo({ duration: 200 }, () => {
                this.advancedOpen = !this.advancedOpen;
              });
            })

            if (this.advancedOpen) {
              this.RowDivider(16)
              this.SelectRow($r('app.string.label_period'), this.periodOptions(),
                this.indexOrZero(PERIODS, this.account.period),
                getString(this.ctx(), 'period_seconds', this.account.period),
                (i: number) => {
                  this.account.period = PERIODS[i];
                })
              this.RowDivider(16)
              this.SelectRow($r('app.string.label_digits'), this.digitsOptions(),
                this.indexOrZero(DIGITS, this.account.digits),
                getString(this.ctx(), 'digits_count', this.account.digits),
                (i: number) => {
                  this.account.digits = DIGITS[i];
                })
              this.RowDivider(16)
              this.SelectRow($r('app.string.label_algorithm'), this.algorithmOptions(),
                Math.max(0, ALGORITHMS.indexOf(this.account.algorithm)),
                this.account.algorithm,
                (i: number) => {
                  this.setAlgorithm(i);
                })
            }
          }
          .cardStyle()
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 24 })
      }
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .width('100%')
      .height('100%')
    }
    .backgroundColor($r('sys.color.background_secondary'))
    .titleBar({
      content: {
        title: { mainTitle: this.isEdit ? $r('app.string.edit_title') : $r('app.string.add_title') },
        menu: {
          value: [{
            content: {
              icon: $r('sys.symbol.checkmark'),
              label: $r('app.string.btn_save'),
              action: () => {
                this.save();
              }
            }
          }]
        }
      },
      style: {
        scrollEffectOpts: {
          enableScrollEffect: true,
          scrollEffectType: ScrollEffectType.GRADIENT_BLUR
        },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        }
      },
      avoidLayoutSafeArea: true,
      enableComponentSafeArea: true
    })
    .bindToScrollable([this.scroller])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .bindSheet($$this.iconSheetOpen, this.IconSheet(), {
      systemMaterial: new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.ULTRA_THICK }),
      detents: [SheetSize.LARGE],
      title: { title: $r('app.string.icon_picker_title') },
      showClose: true,
      preferType: SheetType.BOTTOM
    })
  }
}
