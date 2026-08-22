/** YouTube watch / shorts / youtu.be URLs. Playlists without a video id are Stage 4. */

const ID = /^[A-Za-z0-9_-]{11}$/;

export type ParsedYoutubeUrl =
  | { ok: true; videoId: string; canonical: string; mixNotice: boolean }
  | { ok: false; reason: string };

export function parseYoutubeUrl(raw: string): ParsedYoutubeUrl {
  const trimmed = raw.trim();
  if (trimmed === '') {
    return { ok: false, reason: 'Paste a YouTube URL or 11-character video id.' };
  }
  if (ID.test(trimmed)) {
    return {
      ok: true,
      videoId: trimmed,
      canonical: `https://www.youtube.com/watch?v=${trimmed}`,
      mixNotice: false,
    };
  }

  let url: URL;
  try {
    url = new URL(trimmed);
  } catch {
    return { ok: false, reason: 'That is not a URL. Paste a full YouTube link.' };
  }

  const host = url.hostname.replace(/^www\./, '');
  const list = url.searchParams.get('list');
  const hasList = Boolean(list && list.length > 0);

  if (host === 'youtu.be') {
    const id = url.pathname.replace(/^\//, '').split('/')[0] ?? '';
    if (!ID.test(id)) return { ok: false, reason: 'Could not find a video id in that short link.' };
    return {
      ok: true,
      videoId: id,
      canonical: `https://www.youtube.com/watch?v=${id}`,
      mixNotice: hasList,
    };
  }
  if (host === 'youtube.com' || host === 'm.youtube.com' || host === 'music.youtube.com') {
    const v = url.searchParams.get('v');
    if (v && ID.test(v)) {
      return {
        ok: true,
        videoId: v,
        canonical: `https://www.youtube.com/watch?v=${v}`,
        mixNotice: hasList,
      };
    }
    const shorts = url.pathname.match(/^\/shorts\/([A-Za-z0-9_-]{11})/);
    if (shorts?.[1]) {
      return {
        ok: true,
        videoId: shorts[1],
        canonical: `https://www.youtube.com/watch?v=${shorts[1]}`,
        mixNotice: hasList,
      };
    }
    if (url.pathname.startsWith('/playlist') || (hasList && !v)) {
      return {
        ok: false,
        reason: 'That is a playlist, not a single track. Paste a video link (or a mix URL that still has a video id).',
      };
    }
    return { ok: false, reason: 'Could not find a video id in that YouTube URL.' };
  }
  return { ok: false, reason: 'Only YouTube URLs are supported.' };
}
