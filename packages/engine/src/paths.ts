import path from 'node:path';
import { existsSync } from 'node:fs';

export type ToolPaths = {
  python: string | null;
  ffmpeg: string | null;
  ffprobe: string | null;
  qjs: string | null;
  deno: string | null;
  wheel: string | null;
};

export function firstExisting(candidates: readonly string[]): string | null {
  for (const c of candidates) {
    if (c && existsSync(c)) return c;
  }
  return null;
}

/** Prepend a pure-Python wheel onto PYTHONPATH so `python -m yt_dlp` works. */
export function withWheelOnPath(
  env: NodeJS.ProcessEnv,
  wheel: string | null,
): NodeJS.ProcessEnv {
  if (!wheel) return env;
  const current = env.PYTHONPATH ?? '';
  return {
    ...env,
    PYTHONPATH: current === '' ? wheel : `${wheel}${path.delimiter}${current}`,
  };
}

export function ytDlpModuleArgs(): string[] {
  return ['-m', 'yt_dlp'];
}

export function ffmpegDir(ffmpegPath: string | null): string | undefined {
  if (!ffmpegPath) return undefined;
  return path.dirname(ffmpegPath);
}
