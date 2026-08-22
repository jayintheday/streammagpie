/**
 * helper-paths.ts — bundled ffmpeg / python / qjs / floor wheel.
 * Import FIRST from index.ts. Packaged apps have no Homebrew on PATH.
 */

import { app } from 'electron';
import path from 'node:path';
import { existsSync } from 'node:fs';

const FFMPEG_DIR = 'ffmpeg';
const PYTHON_DIR = 'python';
const JS_DIR = 'js';
const YTDLP_DIR = 'ytdlp';

function setIfUnset(name: string, value: string): void {
  const current = process.env[name];
  if (current !== undefined && current.length > 0) return;
  process.env[name] = value;
}

export function configureBundledHelpers(): void {
  if (!app.isPackaged) return;
  const res = process.resourcesPath;
  setIfUnset('STREAMMAGPIE_FFMPEG', path.join(res, FFMPEG_DIR, 'ffmpeg'));
  setIfUnset('STREAMMAGPIE_FFPROBE', path.join(res, FFMPEG_DIR, 'ffprobe'));
  setIfUnset('STREAMMAGPIE_PYTHON', path.join(res, PYTHON_DIR, 'bin', 'python3'));
  const qjs = path.join(res, JS_DIR, 'qjs');
  const deno = path.join(res, JS_DIR, 'deno');
  if (existsSync(qjs)) setIfUnset('STREAMMAGPIE_QJS', qjs);
  if (existsSync(deno)) setIfUnset('STREAMMAGPIE_DENO', deno);
  setIfUnset('STREAMMAGPIE_FLOOR_WHEEL', path.join(res, YTDLP_DIR, 'yt_dlp.whl'));
}

configureBundledHelpers();

export function supportDir(): string {
  return path.join(app.getPath('userData'), 'extractor');
}
