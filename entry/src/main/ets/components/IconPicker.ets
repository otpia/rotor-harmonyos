import { common } from '@kit.AbilityKit';
import { uiMaterial } from '@kit.ArkUI';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { IconCache } from '../services/IconCache';
import { ICON_IMG, ICON_LIB, ICON_URL, searchIcons } from '../utils/IssuerIcon';
import { IssuerIconEntry } from '../utils/IssuerIconData';

const ROW_HEIGHT = 56;

class IconSource implements IDataSource {
  private items: IssuerIconEntry[] = [];
  private listeners: DataChangeListener[] = [];

  constructor(items: IssuerIconEntry[]) {
    this.items = items;
  }

  setItems(items: IssuerIconEntry[]): void {
    this.items = items;
    for (const l of this.listeners) {
      l.onDataReloaded();
    }
  }

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): IssuerIconEntry {
    return this.items[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const i = this.listeners.indexOf(listener);
    if (i >= 0) {
      this.listeners.splice(i, 1);
    }
  }
}

// 半模态内的图标选择：搜索内置图标，恢复自动识别，从图库导入或按链接下载，结果以 iconKey 回传
@Component
export struct IconPicker {
  @Prop current: string = '';
  onPick: (iconKey: string) => void = () => {
  };
  @State query: string = '';
  @State url: string = '';
  @State busy: boolean = false;
  @State resultCount: number = 0;
  private source: IconSource = new IconSource([]);

  aboutToAppear(): void {
    if (this.current.startsWith(ICON_URL)) {
      this.url = this.current.substring(ICON_URL.length);
    }
    const items = searchIcons('');
    this.source.setItems(items);
    this.resultCount = items.length;
  }

  private ctx(): common.Context {
    return this.getUIContext().getHostContext() as common.Context;
  }

  private toast(msg: ResourceStr): void {
    try {
      this.getUIContext().getPromptAction().showToast({
        message: msg,
        systemMaterial: new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.THICK })
      });
    } catch (e) {
      console.error('[IconPicker.toast]', e);
    }
  }

  private search(v: string): void {
    this.query = v;
    const items = searchIcons(v);
    this.source.setItems(items);
    this.resultCount = items.length;
  }

  private async pickPhoto(): Promise<void> {
    try {
      const opts = new photoAccessHelper.PhotoSelectOptions();
      opts.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      opts.maxSelectNumber = 1;
      const res = await new photoAccessHelper.PhotoViewPicker().select(opts);
      if (res.photoUris.length === 0) {
        return;
      }
      this.busy = true;
      const name = await IconCache.importPhoto(this.ctx(), res.photoUris[0]);
      this.onPick(ICON_IMG + name);
    } catch (e) {
      console.error('[IconPicker.pickPhoto]', e);
      this.toast($r('app.string.icon_read_failed'));
    } finally {
      this.busy = false;
    }
  }

  private async download(): Promise<void> {
    const url = this.url.trim();
    if (!/^https?:\/\/\S+$/i.test(url)) {
      this.toast($r('app.string.icon_url_invalid'));
      return;
    }
    this.busy = true;
    try {
      await IconCache.downloadNow(this.ctx(), url);
      this.onPick(ICON_URL + url);
    } catch (e) {
      console.error('[IconPicker.download]', e);
      this.toast($r('app.string.icon_download_failed'));
    } finally {
      this.busy = false;
    }
  }

  @Builder RowDivider() {
    Divider()
      .color($r('sys.color.comp_divider'))
      .strokeWidth(0.5)
      .margin({ left: 16, right: 16 })
  }

  build() {
    Column({ space: 12 }) {
      Search({ value: this.query, placeholder: $r('app.string.icon_search_hint') })
        .onChange((v: string) => {
          this.search(v);
        })

      Column() {
        Row() {
          Text($r('app.string.icon_auto'))
            .fontSize($r('sys.float.Body_L'))
            .fontColor($r('sys.color.font_primary'))
            .layoutWeight(1)
          if (this.current.length === 0) {
            SymbolGlyph($r('sys.symbol.checkmark'))
              .fontSize(20)
              .fontColor([$r('sys.color.icon_emphasize')])
          }
        }
        .width('100%')
        .height(ROW_HEIGHT)
        .padding({ left: 16, right: 16 })
        .onClick(() => {
          this.onPick('');
        })

        this.RowDivider()

        Row() {
          Text($r('app.string.icon_from_photo'))
            .fontSize($r('sys.float.Body_L'))
            .fontColor($r('sys.color.font_primary'))
            .layoutWeight(1)
          if (this.current.startsWith(ICON_IMG)) {
            SymbolGlyph($r('sys.symbol.checkmark'))
              .fontSize(20)
              .fontColor([$r('sys.color.icon_emphasize')])
          } else {
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(20)
              .fontColor([$r('sys.color.icon_secondary')])
          }
        }
        .width('100%')
        .height(ROW_HEIGHT)
        .padding({ left: 16, right: 16 })
        .enabled(!this.busy)
        .onClick(() => {
          this.pickPhoto();
        })

        this.RowDivider()

        Row({ space: 8 }) {
          TextInput({ text: this.url, placeholder: $r('app.string.icon_url_hint') })
            .type(InputType.URL)
            .fontSize($r('sys.float.Body_L'))
            .backgroundColor(Color.Transparent)
            .padding({ left: 0, right: 0 })
            .height(40)
            .layoutWeight(1)
            .onChange((v: string) => {
              this.url = v;
            })
          if (this.busy) {
            LoadingProgress()
              .width(24)
              .height(24)
          } else {
            Button($r('app.string.icon_download'))
              .buttonStyle(ButtonStyleMode.TEXTUAL)
              .controlSize(ControlSize.SMALL)
              .enabled(this.url.trim().length > 0)
              .onClick(() => {
                this.download();
              })
          }
        }
        .width('100%')
        .height(ROW_HEIGHT)
        .padding({ left: 16, right: 8 })
      }
      .width('100%')
      .backgroundColor($r('sys.color.comp_background_list_card'))
      .borderRadius($r('sys.float.corner_radius_level8'))

      if (this.resultCount === 0) {
        Text($r('app.string.icon_no_result'))
          .fontSize($r('sys.float.Body_M'))
          .fontColor($r('sys.color.font_secondary'))
          .margin({ top: 24 })
      }

      Grid() {
        LazyForEach(this.source, (e: IssuerIconEntry) => {
          GridItem() {
            Column({ space: 6 }) {
              Image(e.icon)
                .width(40)
                .height(40)
                .objectFit(ImageFit.Contain)
                .interpolation(ImageInterpolation.High)
                .draggable(false)
              Text(e.title)
                .fontSize($r('sys.float.Caption_M'))
                .fontColor($r('sys.color.font_secondary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .textAlign(TextAlign.Center)
                .width('100%')
            }
            .width('100%')
            .padding({ top: 10, bottom: 8, left: 4, right: 4 })
            .borderRadius($r('sys.float.corner_radius_level6'))
            .backgroundColor(this.current === ICON_LIB + e.key ?
              $r('sys.color.comp_background_tertiary') : Color.Transparent)
            .onClick(() => {
              this.onPick(ICON_LIB + e.key);
            })
          }
        }, (e: IssuerIconEntry) => e.key)
      }
      .columnsTemplate('repeat(auto-fit, 76)')
      .rowsGap(4)
      .columnsGap(4)
      .cachedCount(4)
      .edgeEffect(EdgeEffect.Spring)
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, bottom: 16 })
  }
}
