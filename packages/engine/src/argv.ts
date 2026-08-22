import { DEFAULT_CLIENT_CHAIN, isDeadWebOnly, playerClientArg } from './clients.js';

export type AudioFormat = 'm4a' | 'mp3' | 'alac';

export type YtDlpJob = {
  url: string;
  outputDir: string;
  format: AudioFormat;
  clientChain?: readonly string[];
  ffmpegPath?: string;
  jsRuntime?: { name: 'qjs' | 'deno'; path: string };
  sleepIntervalSec?: number;
};

export type BuiltArgs = {
  args: string[];
  /** True when the job would use the dead web client with no fallback. */
  usesDeadWebClient: boolean;
};

const PROGRESS_TEMPLATE =
  'progress\t%(progress._percent_str|0)s\t%(progress._speed_str|NA)s\t%(progress._eta_str|NA)s\t%(filename)s';

export function buildYtDlpArgs(job: YtDlpJob): BuiltArgs {
  const chain = job.clientChain ?? DEFAULT_CLIENT_CHAIN;
  const usesDeadWebClient = chain.length === 1 && isDeadWebOnly(chain[0] ?? '');

  const args: string[] = [
    '--no-playlist',
    '--newline',
    '--no-update',
    '--sleep-interval',
    String(job.sleepIntervalSec ?? 1),
    '--extractor-args',
    playerClientArg(chain),
    '--progress-template',
    PROGRESS_TEMPLATE,
    '-P',
    job.outputDir,
    '-o',
    '%(title).200B [%(id)s].%(ext)s',
  ];

  if (job.ffmpegPath) {
    args.push('--ffmpeg-location', job.ffmpegPath);
  }
  if (job.jsRuntime) {
    args.push('--js-runtimes', `${job.jsRuntime.name}:${job.jsRuntime.path}`);
  }

  if (job.format === 'm4a') {
    args.push('-f', '140/bestaudio[ext=m4a]/bestaudio', '--remux-video', 'm4a');
  } else if (job.format === 'mp3') {
    args.push('-x', '--audio-format', 'mp3', '--audio-quality', '0');
  } else {
    args.push('-f', 'bestaudio', '-x', '--audio-format', 'alac');
  }

  args.push('--', job.url);
  return { args, usesDeadWebClient };
}
