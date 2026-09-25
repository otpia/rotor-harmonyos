import { common } from '@kit.AbilityKit';
import { buffer, util } from '@kit.ArkTS';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { http } from '@kit.NetworkKit';
import { ICON_IMG, ICON_URL } from '../utils/IssuerIcon';

// 自定义图标存放在应用 files 目录下
const DIR = 'issuer_icons';
// 位图缩到最长边不超过这个像素再保存
const MAX_SIDE = 192;
// 链接下载的图片不超过 5 MB，图库照片不超过 30 MB
const MAX_BYTES = 5 * 1024 * 1024;
const MAX_PHOTO_BYTES = 30 * 1024 * 1024;
// 下载失败后这段时间内不再自动重试同一链接
const RETRY_MS = 60 * 1000;
const TIMEOUT_MS = 15 * 1000;

// 下载中的请求，同一链接同时只下载一次
const pending: Map<string, Promise<string>> = new Map();
const failedAt: Map<string, number> = new Map();

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

// 链接的缓存文件名，64 位字符串哈希，只用来区分文件
function urlBase(url: string): string {
  let h1 = 0xdeadbeef;
  let h2 = 0x41c6ce57;
  for (let i = 0; i < url.length; i++) {
    const ch = url.charCodeAt(i);
    h1 = Math.imul(h1 ^ ch, 2654435761);
    h2 = Math.imul(h2 ^ ch, 1597334677);
  }
  h1 = Math.imul(h1 ^ (h1 >>> 16), 2246822507) ^ Math.imul(h2 ^ (h2 >>> 13), 3266489909);
  h2 = Math.imul(h2 ^ (h2 >>> 16), 2246822507) ^ Math.imul(h1 ^ (h1 >>> 13), 3266489909);
  return (h2 >>> 0).toString(16).padStart(8, '0') + (h1 >>> 0).toString(16).padStart(8, '0');
}

function looksLikeSvg(data: ArrayBuffer): boolean {
  try {
    const head = buffer.from(data, 0, Math.min(data.byteLength, 1024)).toString('utf-8').toLowerCase();
    return head.includes('<svg');
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

// 位图转成 PNG 保存，SVG 原样保存，返回文件名
async function save(ctx: common.Context, base: string, data: ArrayBuffer): Promise<string> {
  if (data.byteLength === 0 || data.byteLength > MAX_BYTES) {
    throw new Error(`bad size ${data.byteLength}`);
  }
  const svg = looksLikeSvg(data);
  const name = `${base}.${svg ? 'svg' : 'png'}`;
  writeFile(ctx, name, svg ? data : await toPng(data));
  return name;
}

async function fetchAndSave(ctx: common.Context, url: string): Promise<string> {
  const req = http.createHttp();
  try {
    const res = await req.request(url, {
      method: http.RequestMethod.GET,
      expectDataType: http.HttpDataType.ARRAY_BUFFER,
      connectTimeout: TIMEOUT_MS,
      readTimeout: TIMEOUT_MS
    });
    if (res.responseCode !== 200 || !(res.result instanceof ArrayBuffer)) {
      throw new Error(`http ${res.responseCode}`);
    }
    return await save(ctx, urlBase(url), res.result as ArrayBuffer);
  } catch (e) {
    throw new Error(String(e));
  } finally {
    req.destroy();
  }
}

export class IconCache {
  // 返回 iconKey 对应的本地缓存路径，没有缓存时返回空串
  static cachedPath(ctx: common.Context, iconKey: string): string {
    const dir = dirPath(ctx);
    if (iconKey.startsWith(ICON_IMG)) {
      const path = `${dir}/${iconKey.substring(ICON_IMG.length)}`;
      return exists(path) ? path : '';
    }
    if (iconKey.startsWith(ICON_URL)) {
      const base = urlBase(iconKey.substring(ICON_URL.length));
      for (const ext of ['png', 'svg']) {
        const path = `${dir}/${base}.${ext}`;
        if (exists(path)) {
          return path;
        }
      }
    }
    return '';
  }

  static uriOf(path: string): string {
    return fileUri.getUriFromPath(path);
  }

  // 下载链接指向的图片并缓存，失败后一分钟内不再自动重试同一链接
  static download(ctx: common.Context, url: string): Promise<string> {
    const running = pending.get(url);
    if (running !== undefined) {
      return running;
    }
    const last = failedAt.get(url);
    if (last !== undefined && Date.now() - last < RETRY_MS) {
      return Promise.reject(new Error('retry later'));
    }
    const task = fetchAndSave(ctx, url).then((name: string) => {
      pending.delete(url);
      failedAt.delete(url);
      return name;
    }, (e: Error) => {
      pending.delete(url);
      failedAt.set(url, Date.now());
      throw new Error(e.message);
    });
    pending.set(url, task);
    return task;
  }

  // 用户在选择器里点下载时不受重试间隔限制
  static downloadNow(ctx: common.Context, url: string): Promise<string> {
    failedAt.delete(url);
    return IconCache.download(ctx, url);
  }

  // 把图库里选中的图片缩小后存入应用目录，返回写入 iconKey 的文件名
  static async importPhoto(ctx: common.Context, uri: string): Promise<string> {
    const data = readFile(uri, MAX_PHOTO_BYTES);
    const name = `${util.generateRandomUUID(false)}.png`;
    writeFile(ctx, name, await toPng(data));
    return name;
  }
}
