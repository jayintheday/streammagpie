import { describe, expect, it } from 'vitest';
import { parseYoutubeUrl } from '../src/url.js';
import { buildYtDlpArgs } from '../src/argv.js';
import { parseProgressLine } from '../src/progress.js';
import { judgeAudioFormats } from '../src/quality.js';
import { parseManifest, sha256Hex, verifyWheel } from '../src/updater.js';
import { formatDuration, etaSentence, parseProbeJson } from '../src/probe.js';
import { isDeadWebOnly } from '../src/clients.js';

describe('parseYoutubeUrl', () => {
  it('accepts a watch URL', () => {
    const r = parseYoutubeUrl('https://www.youtube.com/watch?v=jNQXAC9IVRw');
    expect(r.ok).toBe(true);
    if (r.ok) expect(r.videoId).toBe('jNQXAC9IVRw');
  });
  it('accepts youtu.be', () => {
    const r = parseYoutubeUrl('https://youtu.be/jNQXAC9IVRw');
    expect(r.ok).toBe(true);
  });
  it('rejects playlists without a video id', () => {
    const r = parseYoutubeUrl('https://www.youtube.com/playlist?list=PLxxxx');
    expect(r.ok).toBe(false);
  });
  it('accepts a mix URL and flags mixNotice', () => {
    const r = parseYoutubeUrl(
      'https://www.youtube.com/watch?v=jNQXAC9IVRw&list=RDjNQXAC9IVRw',
    );
    expect(r.ok).toBe(true);
    if (r.ok) {
      expect(r.videoId).toBe('jNQXAC9IVRw');
      expect(r.mixNotice).toBe(true);
      expect(r.canonical).toBe('https://www.youtube.com/watch?v=jNQXAC9IVRw');
    }
  });
  it('rejects empty', () => {
    expect(parseYoutubeUrl('  ').ok).toBe(false);
  });
});

describe('buildYtDlpArgs', () => {
  it('remuxes m4a with itag 140 first', () => {
    const { args, usesDeadWebClient } = buildYtDlpArgs({
      url: 'https://www.youtube.com/watch?v=jNQXAC9IVRw',
      outputDir: '/tmp/out',
      format: 'm4a',
    });
    expect(usesDeadWebClient).toBe(false);
    expect(args).toContain('-f');
    expect(args.join(' ')).toContain('140');
    expect(args).toContain('--remux-video');
    expect(args).toContain('--no-update');
    expect(args.join(' ')).toContain('player_client=visionos');
  });
  it('alac forces the codec yt-dlp drops', () => {
    const { args } = buildYtDlpArgs({
      url: 'https://www.youtube.com/watch?v=jNQXAC9IVRw',
      outputDir: '/tmp/out',
      format: 'alac',
    });
    expect(args).toContain('-x');
    expect(args[args.indexOf('--audio-format') + 1]).toBe('alac');
    // Without this pair yt-dlp discards its own `-acodec alac` and ffmpeg
    // writes AAC into the .m4a container — silently lossy. The two elements
    // must stay adjacent: the value is one argv element, split by yt-dlp.
    const i = args.indexOf('--postprocessor-args');
    expect(i).toBeGreaterThan(-1);
    expect(args[i + 1]).toBe('ExtractAudio:-acodec alac');
  });
  it('flags a web-only chain', () => {
    const { usesDeadWebClient } = buildYtDlpArgs({
      url: 'https://www.youtube.com/watch?v=jNQXAC9IVRw',
      outputDir: '/tmp/out',
      format: 'mp3',
      clientChain: ['web'],
    });
    expect(usesDeadWebClient).toBe(true);
    expect(isDeadWebOnly('web')).toBe(true);
  });
});

describe('parseProgressLine', () => {
  it('parses a download percent line', () => {
    const p = parseProgressLine('[download]  12.3% of  3.10MiB at  1.20MiB/s ETA 00:07');
    expect(p?.percent).toBe(12.3);
    expect(p?.eta).toBe('00:07');
  });
  it('parses the template line', () => {
    const p = parseProgressLine('progress\t45.0\t2.1MiB/s\t00:12\tsong.m4a');
    expect(p?.percent).toBe(45);
    expect(p?.filename).toBe('song.m4a');
  });
});

describe('judgeAudioFormats', () => {
  it('fails with no audio-only formats', () => {
    const v = judgeAudioFormats([{ vcodec: 'avc1', acodec: 'none', height: 360 }]);
    expect(v.ok).toBe(false);
  });
  it('passes itag 140', () => {
    const v = judgeAudioFormats([{ format_id: '140', acodec: 'mp4a.40.2', vcodec: 'none', abr: 128 }]);
    expect(v.ok).toBe(true);
  });
});

describe('probe helpers', () => {
  it('formats duration', () => {
    expect(formatDuration(424)).toBe('7:04');
    expect(formatDuration(null)).toBe('');
  });
  it('parses -J title and thumbnail', () => {
    // Synthetic title, deliberately. Hard rule 6 in docs/DISTRIBUTION.md: no
    // real video or track names in this repo, tests included. The em dash is
    // the part that matters here — it is the character a title is most likely
    // to carry and most likely to be mangled by. Keep it; do not "improve"
    // this into something real.
    const m = parseProbeJson(
      JSON.stringify({
        title: 'Example Artist — Example Track',
        duration: 424,
        id: 'abc',
        thumbnail: 'https://i.ytimg.com/vi/abc/default.jpg',
        thumbnails: [{ url: 'https://i.ytimg.com/vi/abc/default.jpg' }, { url: 'https://i.ytimg.com/vi/abc/max.jpg' }],
      }),
    );
    expect(m.title).toBe('Example Artist — Example Track');
    expect(m.durationSec).toBe(424);
    expect(m.thumbnailUrl).toContain('max.jpg');
  });
  it('writes an eta sentence', () => {
    expect(etaSentence(64, '00:04', 424)).toMatch(/64%/);
    expect(etaSentence(64, '00:04', 424)).toMatch(/second/);
  });
});
describe('manifest', () => {
  it('parses a valid manifest', () => {
    const m = parseManifest({
      ytdlp_version: '2026.08.19',
      wheel_url: 'https://github.com/example/r/yt_dlp.whl',
      sha256: 'a'.repeat(64),
      client_chain: ['visionos', 'tv'],
      notice: null,
    });
    expect(m.client_chain[0]).toBe('visionos');
  });
  it('verifies wheel hash', () => {
    const bytes = Buffer.from('hello');
    const hex = sha256Hex(bytes);
    expect(() => verifyWheel(bytes, hex)).not.toThrow();
    expect(() => verifyWheel(bytes, 'b'.repeat(64))).toThrow(/mismatch/);
  });
});
