import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { ICON_IMG } from '../utils/IssuerIcon';

// 自定义图标存放在应用 files 目录下
const DIR = 'issuer_icons';
// 缩到最长边不超过这个像素再保存
const MAX_SIDE = 192;
// 图库照片不超过 30 MB
const MAX_PHOTO_BYTES = 30 * 1024 * 1024;

function dirPath(ctx: common.Context): string {
  const dir = `${ctx.filesDir}/${DIR}`;
  try {
    if (!fileIo.accessSync(dir)) {
      fileIo.mkdirSync(dir);
    }
  } catch (e) {
    console.error('[IconCache.dirPath]', e);
  }
  return dir;
}

function exists(path: string): boolean {
  try {
    return fileIo.accessSync(path);
  } catch (e) {
    return false;
  }
}

function readFile(uri: string, max: number): ArrayBuffer {
  let fd = -1;
  try {
    fd = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY).fd;
    const size = fileIo.statSync(fd).size;
    if (size <= 0 || size > max) {
      throw new Error(`bad size ${size}`);
    }
    const data = new ArrayBuffer(size);
    fileIo.readSync(fd, data);
    return data;
  } catch (e) {
    throw new Error(String(e));
  } finally {
    if (fd >= 0) {
      try {
        fileIo.closeSync(fd);
      } catch (e) {
        console.error('[IconCache.readFile]', e);
      }
    }
  }
}

function writeFile(ctx: common.Context, name: string, data: ArrayBuffer): void {
  let fd = -1;
  try {
    fd = fileIo.openSync(`${dirPath(ctx)}/${name}`,
      fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC).fd;
    fileIo.writeSync(fd, data);
  } catch (e) {
    throw new Error(String(e));
  } finally {
    if (fd >= 0) {
      try {
        fileIo.closeSync(fd);
      } catch (e) {
        console.error('[IconCache.writeFile]', e);
      }
    }
  }
}

// 解码后按比例缩小并转成 PNG
async function toPng(data: ArrayBuffer): Promise<ArrayBuffer> {
  const source = image.createImageSource(data);
  const packer = image.createImagePacker();
  let pixelMap: image.PixelMap | undefined = undefined;
  try {
    const info = await source.getImageInfo();
    const w = info.size.width;
    const h = info.size.height;
    if (w <= 0 || h <= 0) {
      throw new Error('empty image');
    }
    const scale = Math.min(1, MAX_SIDE / Math.max(w, h));
    pixelMap = await source.createPixelMap({
      desiredSize: { width: Math.max(1, Math.round(w * scale)), height: Math.max(1, Math.round(h * scale)) }
    });
    return await packer.packToData(pixelMap, { format: 'image/png', quality: 100 });
  } catch (e) {
    throw new Error(String(e));
  } finally {
    if (pixelMap !== undefined) {
      pixelMap.release();
    }
    packer.release();
    source.release();
  }
}

export class IconCache {
  // 返回图库图标的本地路径，文件不存在时返回空串
  static cachedPath(ctx: common.Context, iconKey: string): string {
    if (!iconKey.startsWith(ICON_IMG)) {
      return '';
    }
    const path = `${dirPath(ctx)}/${iconKey.substring(ICON_IMG.length)}`;
    return exists(path) ? path : '';
  }

  static uriOf(path: string): string {
    return fileUri.getUriFromPath(path);
  }

  // 把图库里选中的图片缩小后存入应用目录，返回写入 iconKey 的文件名
  static async importPhoto(ctx: common.Context, uri: string): Promise<string> {
    const data = readFile(uri, MAX_PHOTO_BYTES);
    const name = `${util.generateRandomUUID(false)}.png`;
    writeFile(ctx, name, await toPng(data));
    return name;
  }
}
