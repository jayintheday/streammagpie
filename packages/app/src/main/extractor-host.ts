import { BrowserWindow, clipboard, dialog, net, shell } from 'electron';
import { randomUUID } from 'node:crypto';
import { mkdir, readFile, rename, stat, writeFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import path from 'node:path';
import { app } from 'electron';
import {
  DEFAULT_CLIENT_CHAIN,
  buildProbeArgs,
  etaSentence,
  formatDuration,
  parseProbeJson,
  parseYoutubeUrl,
  spawnYtDlp,
  spawnYtDlpArgv,
  withWheelOnPath,
  ytDlpModuleArgs,
  type AudioFormat,
} from '@streammagpie/engine';
import {
  PALETTE_WINDOW_BG,
  parsePalette,
  type AppViewState,
  type JobView,
  type ProbeResult,
  type Sleeve,
  type StartJobParams,
  type UiPalette,
} from '../shared/ipc.js';
import { resolveTools, type ResolvedTools } from './resolve-tools.js';
import { checkAndApplyExtractor, loadClientChain, rollbackExtractor } from './extractor-update.js';

const HISTORY_MAX = 30;

type Prefs = { outputDir: string | null; format: AudioFormat; palette: UiPalette };

export function thumbsDir(): string {
  return path.join(app.getPath('userData'), 'thumbs');
}

export function thumbFile(videoId: string): string {
  return path.join(thumbsDir(), `${videoId}.jpg`);
}

export function thumbRef(videoId: string): string {
  return `smthumb://t/${videoId}`;
}

function formatLabel(format: AudioFormat): string {
  if (format === 'm4a') return 'Best quality · m4a';
  if (format === 'mp3') return 'MP3 — compatibility, slight quality loss';
  return 'ALAC';
}

function folderLabel(dir: string | null): string {
  if (!dir) return 'Desktop';
  const home = app.getPath('home');
  if (dir.startsWith(home)) return `~${dir.slice(home.length)}`;
  return path.basename(dir);
}

export class ExtractorHost {
  private win: BrowserWindow | null = null;
  private prefs: Prefs = { outputDir: null, format: 'm4a', palette: 'coral' };
  private current: JobView | null = null;
  private history: JobView[] = [];
  private notice: string | null = null;
  private extractorVersion: string | null = null;
  private childKill: (() => void) | null = null;
  private busy = false;
  private lastSleeve: Sleeve | null = null;
  private lastSaved: JobView | null = null;

  attach(win: BrowserWindow): void {
    this.win = win;
  }

  async boot(): Promise<void> {
    await this.loadPrefs();
    if (!this.prefs.outputDir) {
      this.prefs.outputDir = app.getPath('desktop');
      await this.savePrefs();
    }
    await this.loadHistory();
    try {
      const r = await checkAndApplyExtractor();
      if (r.notice) this.notice = r.notice;
      if (r.manifest) this.extractorVersion = r.manifest.ytdlp_version;
    } catch (err) {
      this.notice = err instanceof Error ? err.message : String(err);
    }
    const t = setInterval(() => {
      void checkAndApplyExtractor()
        .then((r) => {
          if (r.notice) {
            this.notice = r.notice;
            this.emitNotice();
          }
        })
        .catch(() => undefined);
    }, 4 * 60 * 60 * 1000);
    t.unref();
  }

  getState(): AppViewState {
    return {
      outputDir: this.prefs.outputDir,
      outputLabel: folderLabel(this.prefs.outputDir),
      format: this.prefs.format,
      formatLabel: formatLabel(this.prefs.format),
      palette: this.prefs.palette,
      current: this.current,
      lastSaved: this.lastSaved,
      history: this.history,
      notice: this.notice,
      extractorVersion: this.extractorVersion,
    };
  }

  parseUrl(url: string) {
    const r = parseYoutubeUrl(url);
    if (!r.ok) return r;
    return { ok: true as const, canonical: r.canonical, mixNotice: r.mixNotice };
  }

  readClipboard(): string {
    return clipboard.readText();
  }

  async probe(url: string): Promise<ProbeResult> {
    const parsed = parseYoutubeUrl(url);
    if (!parsed.ok) return parsed;

    let tools: ResolvedTools;
    try {
      tools = resolveTools();
    } catch (err) {
      return { ok: false, reason: err instanceof Error ? err.message : String(err) };
    }

    const chain = (await loadClientChain()) ?? [...DEFAULT_CLIENT_CHAIN];
    const js = jsRuntime(tools);
    const built = buildProbeArgs({
      url: parsed.canonical,
      clientChain: chain,
      ...(tools.ffmpeg ? { ffmpegPath: tools.ffmpeg } : {}),
      ...(js ? { jsRuntime: js } : {}),
    });
    const ytdlpBin = tools.ytdlpBin;
    const useBin = tools.wheel === null && ytdlpBin !== null;
    const executable = useBin ? ytdlpBin : tools.python;
    const env = withWheelOnPath({ ...process.env }, tools.wheel);
    const { done } = spawnYtDlpArgv(
      executable,
      useBin ? [] : ytDlpModuleArgs(),
      built.args,
      env,
    );
    const result = await done;
    if (result.code !== 0) {
      return { ok: false, reason: listenerError(result.stderr) };
    }
    let meta;
    try {
      meta = parseProbeJson(result.stdout);
    } catch {
      return { ok: false, reason: 'Could not read that video. Try a different link.' };
    }
    const videoId = meta.videoId ?? parsed.videoId;
    const thumb = await cacheThumbnail(videoId, meta.thumbnailUrl);
    const sleeve: Sleeve = {
      title: meta.title,
      durationSec: meta.durationSec,
      durationLabel: formatDuration(meta.durationSec),
      thumbnailUrl: thumb,
      mixNotice: parsed.mixNotice,
      videoId,
    };
    this.lastSleeve = sleeve;
    this.lastSaved = null;
    const id = randomUUID();
    this.current = {
      id,
      url: parsed.canonical,
      title: sleeve.title,
      format: this.prefs.format,
      phase: 'confirm',
      percent: null,
      speed: null,
      eta: null,
      progressLine: '',
      error: null,
      errorDetail: null,
      outputPath: null,
      bytes: null,
      folderLabel: folderLabel(this.prefs.outputDir),
      finishedAt: null,
      sleeve,
    };
    this.emitJob();
    return { ok: true, canonical: parsed.canonical, mixNotice: parsed.mixNotice, sleeve };
  }

  async chooseFolder(): Promise<string | null> {
    const res = await dialog.showOpenDialog({
      properties: ['openDirectory', 'createDirectory'],
      title: 'Save audio to',
    });
    if (res.canceled || !res.filePaths[0]) return null;
    this.prefs.outputDir = res.filePaths[0];
    await this.savePrefs();
    return this.prefs.outputDir;
  }

  async setFormat(format: AudioFormat): Promise<void> {
    this.prefs.format = format;
    await this.savePrefs();
  }

  windowBackground(): string {
    return PALETTE_WINDOW_BG[this.prefs.palette];
  }

  async setPalette(palette: UiPalette): Promise<void> {
    this.prefs.palette = parsePalette(palette);
    await this.savePrefs();
    this.win?.setBackgroundColor(this.windowBackground());
  }

  async startJob(params: StartJobParams): Promise<{ ok: true } | { ok: false; reason: string }> {
    if (this.busy) return { ok: false, reason: 'Already saving a track. Stop it first.' };
    const parsed = parseYoutubeUrl(params.url);
    if (!parsed.ok) return { ok: false, reason: parsed.reason };
    if (!this.prefs.outputDir) {
      this.prefs.outputDir = app.getPath('desktop');
    }
    const outputDir = this.prefs.outputDir;

    let tools;
    try {
      tools = resolveTools();
    } catch (err) {
      return { ok: false, reason: err instanceof Error ? err.message : String(err) };
    }

    const sleeve = this.lastSleeve;
    const id = this.current?.url === parsed.canonical ? this.current.id : randomUUID();
    const job: JobView = {
      id,
      url: parsed.canonical,
      title: sleeve?.title ?? parsed.canonical,
      format: this.prefs.format,
      phase: 'running',
      percent: 0,
      speed: null,
      eta: null,
      progressLine: 'Saving audio…',
      error: null,
      errorDetail: null,
      outputPath: null,
      bytes: null,
      folderLabel: folderLabel(outputDir),
      finishedAt: null,
      sleeve,
    };
    this.current = job;
    this.busy = true;
    this.emitJob();

    const chain = (await loadClientChain()) ?? [...DEFAULT_CLIENT_CHAIN];
    const js = jsRuntime(tools);
    const ytdlpBin = tools.ytdlpBin;
    const useBin = tools.wheel === null && ytdlpBin !== null;
    const executable = useBin ? ytdlpBin : tools.python;
    const env = withWheelOnPath({ ...process.env }, tools.wheel);
    const { child, done } = spawnYtDlp(
      executable,
      useBin ? [] : ytDlpModuleArgs(),
      {
        url: parsed.canonical,
        outputDir,
        format: this.prefs.format,
        clientChain: chain,
        ...(tools.ffmpeg ? { ffmpegPath: tools.ffmpeg } : {}),
        ...(js ? { jsRuntime: js } : {}),
      },
      {
        onProgress: (p) => {
          if (!this.current || this.current.id !== id) return;
          const file = p.filename && !p.filename.startsWith('http') ? p.filename : this.current.outputPath;
          this.current = {
            ...this.current,
            percent: p.percent,
            speed: p.speed,
            eta: p.eta,
            progressLine: etaSentence(p.percent, p.eta, this.current.sleeve?.durationSec ?? null),
            outputPath: file,
          };
          this.emitJob();
        },
      },
      env,
    );
    this.childKill = () => {
      child.kill('SIGTERM');
    };

    void done.then(async (result) => {
      this.childKill = null;
      this.busy = false;
      if (!this.current || this.current.id !== id) return;
      if (result.code === 0) {
        const out = await newestFile(outputDir, parsed.videoId);
        let bytes: number | null = null;
        if (out) {
          try {
            bytes = (await stat(out)).size;
          } catch {
            bytes = null;
          }
        }
        const doneJob = {
          ...this.current,
          phase: 'ok' as const,
          percent: 100,
          progressLine: '',
          outputPath: out ?? this.current.outputPath,
          bytes,
          finishedAt: Date.now(),
        };
        this.pushHistory(doneJob);
        this.lastSaved = doneJob;
        this.current = null;
        this.emitJob();
        return;
      } else {
        this.current = {
          ...this.current,
          phase: 'error',
          error: listenerError(result.stderr),
          errorDetail: result.stderr.trim() || null,
          finishedAt: Date.now(),
        };
        if (/No video formats found|HTTP Error 403|n-sig|PO Token/i.test(result.stderr)) {
          await rollbackExtractor();
        }
      }
      this.pushHistory(this.current);
      this.emitJob();
    });

    return { ok: true };
  }

  cancelJob(): void {
    this.childKill?.();
    this.childKill = null;
    this.busy = false;
    if (this.current?.phase === 'running') {
      this.current = {
        ...this.current,
        phase: 'cancelled',
        finishedAt: Date.now(),
        error: 'Stopped.',
        progressLine: '',
      };
      this.emitJob();
    }
  }

  dismiss(): void {
    if (this.busy) return;
    this.current = null;
    this.emitJob();
  }

  removeRecent(jobId: string): void {
    if (typeof jobId !== 'string' || jobId === '') return;
    const target = this.history.find((h) => h.id === jobId);
    if (!target) return;
    this.history = this.history.filter((h) => !sameTrack(h, target));
    if (this.lastSaved && sameTrack(this.lastSaved, target)) this.lastSaved = null;
    void this.saveHistory();
    this.emitJob();
  }

  async play(filePath: string): Promise<void> {
    if (!safeUserPath(filePath)) return;
    await shell.openPath(filePath);
  }

  showInFinder(filePath: string): void {
    if (!safeUserPath(filePath)) return;
    shell.showItemInFolder(filePath);
  }

  async rename(filePath: string): Promise<string | null> {
    if (!safeUserPath(filePath)) return null;
    const dir = path.dirname(filePath);
    const ext = path.extname(filePath);
    const res = await dialog.showSaveDialog({
      defaultPath: filePath,
      filters: [{ name: 'Audio', extensions: [ext.replace('.', '') || 'm4a'] }],
    });
    if (res.canceled || !res.filePath) return null;
    const dest = res.filePath.endsWith(ext) ? res.filePath : `${res.filePath}${ext}`;
    await rename(filePath, dest);
    if (this.current?.outputPath === filePath) {
      this.current = { ...this.current, outputPath: dest };
      this.emitJob();
    }
    return dest;
  }

  async checkExtractor(): Promise<void> {
    try {
      const r = await checkAndApplyExtractor();
      this.notice = r.notice;
      if (r.manifest) this.extractorVersion = r.manifest.ytdlp_version;
    } catch (err) {
      this.notice = err instanceof Error ? err.message : String(err);
    }
    this.emitNotice();
  }

  aboutPayload(): { extractorVersion: string | null } {
    return { extractorVersion: this.extractorVersion };
  }

  private pushHistory(job: JobView): void {
    this.history = [job, ...this.history.filter((h) => !sameTrack(h, job))].slice(0, HISTORY_MAX);
    void this.saveHistory();
  }

  private emitJob(): void {
    this.win?.webContents.send('sm:job', this.current);
  }

  private emitNotice(): void {
    this.win?.webContents.send('sm:notice', this.notice);
  }

  private prefsPath(): string {
    return path.join(app.getPath('userData'), 'prefs.json');
  }

  private historyPath(): string {
    return path.join(app.getPath('userData'), 'history.json');
  }

  private async loadPrefs(): Promise<void> {
    try {
      const raw = JSON.parse(await readFile(this.prefsPath(), 'utf8')) as Prefs;
      if (raw.outputDir) this.prefs.outputDir = raw.outputDir;
      if (raw.format === 'm4a' || raw.format === 'mp3' || raw.format === 'alac') {
        this.prefs.format = raw.format;
      }
      this.prefs.palette = parsePalette(raw.palette);
    } catch {
      /* first run */
    }
  }

  private async savePrefs(): Promise<void> {
    await writeFile(this.prefsPath(), JSON.stringify(this.prefs, null, 2));
  }

  private async loadHistory(): Promise<void> {
    try {
      const raw = JSON.parse(await readFile(this.historyPath(), 'utf8')) as JobView[];
      if (Array.isArray(raw)) this.history = collapseHistory(raw).slice(0, HISTORY_MAX);
    } catch {
      this.history = [];
    }
  }

  private async saveHistory(): Promise<void> {
    const slim = this.history.map((h) => ({
      ...h,
      errorDetail: h.errorDetail && h.errorDetail.length > 4000 ? h.errorDetail.slice(-4000) : h.errorDetail,
    }));
    await writeFile(this.historyPath(), JSON.stringify(slim, null, 2));
  }
}

function trackKey(job: JobView): string {
  const id = job.sleeve?.videoId;
  if (id) return `id:${id}`;
  const fromFile = (job.outputPath ?? job.title).match(/\[([A-Za-z0-9_-]{11})\]/);
  if (fromFile?.[1]) return `id:${fromFile[1]}`;
  if (job.url) return `url:${job.url}`;
  return `job:${job.id}`;
}

function sameTrack(a: JobView, b: JobView): boolean {
  return trackKey(a) === trackKey(b);
}

function collapseHistory(items: JobView[]): JobView[] {
  const seen = new Set<string>();
  const out: JobView[] = [];
  for (const job of items) {
    const key = trackKey(job);
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(job);
  }
  return out;
}

function jsRuntime(tools: ResolvedTools) {
  return tools.qjs
    ? { name: 'qjs' as const, path: tools.qjs }
    : tools.deno
      ? { name: 'deno' as const, path: tools.deno }
      : undefined;
}

async function cacheThumbnail(videoId: string, url: string | null): Promise<string | null> {
  if (!url || !/^[A-Za-z0-9_-]{11}$/.test(videoId)) return null;
  await mkdir(thumbsDir(), { recursive: true });
  const dest = thumbFile(videoId);
  try {
    if (existsSync(dest)) return thumbRef(videoId);
    const res = await net.fetch(url);
    if (!res.ok) return null;
    const buf = Buffer.from(await res.arrayBuffer());
    await writeFile(dest, buf);
    return thumbRef(videoId);
  } catch {
    return null;
  }
}

async function newestFile(dir: string, videoId: string): Promise<string | null> {
  const { readdir } = await import('node:fs/promises');
  try {
    const names = await readdir(dir);
    const hits = names.filter((n) => n.includes(`[${videoId}]`));
    if (hits.length === 0) return null;
    let best: { p: string; m: number } | null = null;
    for (const n of hits) {
      const p = path.join(dir, n);
      const s = await stat(p);
      if (!best || s.mtimeMs > best.m) best = { p, m: s.mtimeMs };
    }
    return best?.p ?? null;
  } catch {
    return null;
  }
}

function safeUserPath(filePath: string): boolean {
  return path.isAbsolute(filePath) && !filePath.includes('\0');
}

function listenerError(stderr: string): string {
  if (/No video formats found/i.test(stderr)) {
    return "One link didn't work. YouTube sent no audio for this client. A retry often clears it.";
  }
  if (/Sign in to confirm/i.test(stderr)) {
    return 'YouTube asked for a sign-in. This version does not log in. Try another track, or wait.';
  }
  if (/HTTP Error 403/i.test(stderr)) {
    return "One link didn't work. YouTube blocked the request. This usually clears on a retry.";
  }
  if (/Stopped|SIGTERM/i.test(stderr)) return 'Stopped.';
  return "One link didn't work. YouTube blocked the request. This usually clears on a retry.";
}
