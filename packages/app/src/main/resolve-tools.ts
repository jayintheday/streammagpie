import { app } from 'electron';
import { existsSync } from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { firstExisting } from '@streammagpie/engine';
import { supportDir } from './helper-paths.js';

function which(bin: string): string | null {
  try {
    const out = execFileSync('/usr/bin/which', [bin], { encoding: 'utf8' }).trim();
    return out || null;
  } catch {
    return null;
  }
}

export type ResolvedTools = {
  python: string;
  ffmpeg: string | null;
  qjs: string | null;
  deno: string | null;
  wheel: string | null;
  /** Official CLI on PATH. Used only when no wheel is available. */
  ytdlpBin: string | null;
};

function floorWheelCandidates(): string[] {
  const res = process.resourcesPath ?? '';
  const appPath = app.getAppPath();
  return [
    process.env.STREAMMAGPIE_FLOOR_WHEEL ?? '',
    path.join(res, 'ytdlp', 'yt_dlp.whl'),
    // electron dist/main → repo vendor (dev)
    path.join(appPath, '..', '..', 'vendor', 'ytdlp', 'yt_dlp.whl'),
    path.join(appPath, '..', '..', '..', '..', 'vendor', 'ytdlp', 'yt_dlp.whl'),
    path.join(process.cwd(), 'vendor', 'ytdlp', 'yt_dlp.whl'),
    path.join(process.cwd(), '..', '..', 'vendor', 'ytdlp', 'yt_dlp.whl'),
  ];
}

export function resolveTools(): ResolvedTools {
  const python =
    process.env.STREAMMAGPIE_PYTHON ||
    firstExisting([
      path.join(process.resourcesPath ?? '', 'python', 'bin', 'python3'),
      which('python3') ?? '',
    ]);
  if (!python) {
    throw new Error('No Python interpreter found. Install Python 3 or vendor python-build-standalone.');
  }

  const ffmpeg =
    process.env.STREAMMAGPIE_FFMPEG ||
    firstExisting([
      path.join(process.resourcesPath ?? '', 'ffmpeg', 'ffmpeg'),
      which('ffmpeg') ?? '',
    ]);

  const qjs =
    process.env.STREAMMAGPIE_QJS ||
    firstExisting([path.join(process.resourcesPath ?? '', 'js', 'qjs'), which('qjs') ?? '']);
  const deno =
    process.env.STREAMMAGPIE_DENO ||
    firstExisting([path.join(process.resourcesPath ?? '', 'js', 'deno'), which('deno') ?? '']);

  const liveWheel = path.join(supportDir(), 'live', 'yt_dlp.whl');
  const floor = firstExisting(floorWheelCandidates());
  const wheel = existsSync(liveWheel) ? liveWheel : floor;
  const ytdlpBin = which('yt-dlp');

  if (!wheel && !ytdlpBin) {
    throw new Error(
      'yt-dlp is not installed. Run `bash scripts/vendor-ytdlp.sh` from the repo, or `brew install yt-dlp`.',
    );
  }

  return { python, ffmpeg, qjs, deno, wheel, ytdlpBin };
}
