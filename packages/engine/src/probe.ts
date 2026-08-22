import { DEFAULT_CLIENT_CHAIN, isDeadWebOnly, playerClientArg } from './clients.js';
import type { YtDlpJob } from './argv.js';

export type ProbeMeta = {
  title: string;
  durationSec: number | null;
  thumbnailUrl: string | null;
  videoId: string | null;
};

export function buildProbeArgs(job: Pick<YtDlpJob, 'url' | 'clientChain' | 'ffmpegPath' | 'jsRuntime'>): {
  args: string[];
  usesDeadWebClient: boolean;
} {
  const chain = job.clientChain ?? DEFAULT_CLIENT_CHAIN;
  const usesDeadWebClient = chain.length === 1 && isDeadWebOnly(chain[0] ?? '');
  const args: string[] = [
    '--no-playlist',
    '--no-update',
    '--skip-download',
    '-J',
    '--extractor-args',
    playerClientArg(chain),
  ];
  if (job.ffmpegPath) args.push('--ffmpeg-location', job.ffmpegPath);
  if (job.jsRuntime) args.push('--js-runtimes', `${job.jsRuntime.name}:${job.jsRuntime.path}`);
  args.push('--', job.url);
  return { args, usesDeadWebClient };
}

export function parseProbeJson(raw: string): ProbeMeta {
  const data = JSON.parse(raw) as Record<string, unknown>;
  const title = typeof data.title === 'string' && data.title !== '' ? data.title : 'Untitled';
  const durationSec = typeof data.duration === 'number' && Number.isFinite(data.duration) ? data.duration : null;
  const videoId = typeof data.id === 'string' ? data.id : null;
  let thumbnailUrl: string | null = typeof data.thumbnail === 'string' ? data.thumbnail : null;
  const thumbs = data.thumbnails;
  if (Array.isArray(thumbs) && thumbs.length > 0) {
    const last = thumbs[thumbs.length - 1];
    if (last && typeof last === 'object' && last !== null && 'url' in last && typeof last.url === 'string') {
      thumbnailUrl = last.url;
    }
  }
  return { title, durationSec, thumbnailUrl, videoId };
}

export function formatDuration(sec: number | null): string {
  if (sec === null || !Number.isFinite(sec) || sec < 0) return '';
  const s = Math.round(sec);
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const r = s % 60;
  if (h > 0) return `${h}:${String(m).padStart(2, '0')}:${String(r).padStart(2, '0')}`;
  return `${m}:${String(r).padStart(2, '0')}`;
}

export function etaSentence(percent: number | null, eta: string | null, durationSec: number | null): string {
  const pct = percent !== null ? Math.round(percent) : null;
  let left = '';
  if (eta && eta !== 'NA') {
    left = etaToWords(eta);
  } else if (pct !== null && durationSec && pct > 0 && pct < 100) {
    const remain = durationSec * (1 - pct / 100);
    left = secondsToWords(remain);
  }
  if (pct === null && !left) return 'Saving audio…';
  if (pct !== null && left) return `Saving audio — ${pct}%, ${left}`;
  if (pct !== null) return `Saving audio — ${pct}%`;
  return `Saving audio — ${left}`;
}

function etaToWords(eta: string): string {
  const m = /^(\d+):(\d+)(?::(\d+))?$/.exec(eta.trim());
  if (!m) return `about ${eta} left`;
  if (m[3] !== undefined) {
    const sec = Number(m[1]) * 3600 + Number(m[2]) * 60 + Number(m[3]);
    return secondsToWords(sec);
  }
  const sec = Number(m[1]) * 60 + Number(m[2]);
  return secondsToWords(sec);
}

function secondsToWords(sec: number): string {
  const n = Math.max(1, Math.round(sec));
  if (n < 60) return `about ${n} second${n === 1 ? '' : 's'} left`;
  const min = Math.round(n / 60);
  return `about ${min} minute${min === 1 ? '' : 's'} left`;
}
