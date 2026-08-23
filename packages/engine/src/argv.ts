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
    // ⚠ ALAC NEEDS THE CODEC FORCED, BECAUSE yt-dlp DROPS ITS OWN. The
    // ACODECS table carries the right pair — `'alac': ('m4a', None,
    // ('-acodec', 'alac'))` — but `FFmpegExtractAudioPP.run()` then does
    // `more_opts = self._quality_args(acodec)`, which REPLACES `more_opts`
    // rather than extending it. alac's encoder entry is `None` and not
    // `'copy'`, so that branch is taken, the `-acodec alac` pair is discarded,
    // and ffmpeg gets a bare `.m4a` output — which it defaults to AAC. The
    // lossless option silently returned a lossy file indistinguishable from
    // the m4a one. `[verified: source — yt-dlp 2026.8.19,
    // yt_dlp/postprocessor/ffmpeg.py]`
    //
    // `--postprocessor-args` survives the overwrite: it reaches the ffmpeg
    // command through `_configuration_args()` on the output file, which
    // `_quality_args()` never touches. Exactly two argv elements — yt-dlp
    // splits the value itself. Forward-safe: if a later wheel fixes this
    // upstream, `-acodec alac` simply appears twice and ffmpeg honours the
    // last one. `[verified: run 2026-08-23 — codec_name=alac,
    // bits_per_raw_sample=24, 2,441,748 bytes, against 310,517 bytes for the
    // dropped-flag path on the same 19.006 s source]`
    args.push('--postprocessor-args', 'ExtractAudio:-acodec alac');
  }

  args.push('--', job.url);
  return { args, usesDeadWebClient };
}
