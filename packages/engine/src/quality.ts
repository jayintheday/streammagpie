/** SABR / web-client junk: a "success" that only got 360p-class video or no audio. */

export type FormatProbe = {
  acodec?: string | null;
  vcodec?: string | null;
  height?: number | null;
  abr?: number | null;
  format_id?: string | null;
  protocol?: string | null;
};

export type QualityVerdict =
  | { ok: true }
  | { ok: false; reason: string };

export function judgeAudioFormats(formats: readonly FormatProbe[]): QualityVerdict {
  const audio = formats.filter((f) => {
    const a = f.acodec && f.acodec !== 'none';
    const vNone = !f.vcodec || f.vcodec === 'none';
    return Boolean(a && vNone);
  });
  if (audio.length === 0) {
    return {
      ok: false,
      reason:
        'No audio-only formats came back. YouTube may be serving SABR-only streams for this client. Wait for an extractor update, or try again later.',
    };
  }
  const usable = audio.filter((f) => (f.abr ?? 0) >= 64 || formatLooksAacOrOpus(f));
  if (usable.length === 0) {
    return {
      ok: false,
      reason:
        'Only very low-bitrate audio was offered. That is usually a bot or SABR fallback, not a real extract.',
    };
  }
  return { ok: true };
}

function formatLooksAacOrOpus(f: FormatProbe): boolean {
  const id = f.format_id ?? '';
  const codec = (f.acodec ?? '').toLowerCase();
  return id === '140' || id === '251' || codec.includes('aac') || codec.includes('opus') || codec.includes('mp4a');
}
