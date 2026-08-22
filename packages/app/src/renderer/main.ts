import type { AppViewState, AudioFormat, JobView, UiPalette } from '../shared/ipc.js';
import { parsePalette } from '../shared/ipc.js';

const api = window.streammagpie;

const confirm = el('#view-confirm');
const pulling = el('#view-pulling');
const landed = el('#view-landed');
const waitError = el('#wait-error') as HTMLParagraphElement;
const urlForm = el('#url-form') as HTMLFormElement;
const urlInput = el('#url') as HTMLInputElement;
const lookupBtn = el('#btn-lookup') as HTMLButtonElement;
const lookupView = el('#view-lookup');
const justSaved = el('#just-saved');
const savedArt = el('#saved-art') as HTMLImageElement;
const savedTitle = el('#saved-title');
const savedMeta = el('#saved-meta');
const heroTitle = el('#hero-title');
const heroHint = el('#hero-hint');
const sleeveArt = el('#sleeve-art') as HTMLImageElement;
const sleeveTitle = el('#sleeve-title');
const sleeveMeta = el('#sleeve-meta');
const mixNotice = el('#mix-notice');
const pullArt = el('#pull-art') as HTMLImageElement;
const pullTitle = el('#pull-title');
const pullLine = el('#pull-line');
const pullBar = el('#pull-bar') as HTMLProgressElement;
const landArt = el('#land-art') as HTMLImageElement;
const landTitle = el('#land-title');
const landLine = el('#land-line');
const landError = el('#land-error') as HTMLParagraphElement;
const landDetails = el('#land-details') as HTMLDetailsElement;
const landDetailText = el('#land-detail-text');
const landOk = el('#land-ok-actions');
const landErr = el('#land-err-actions');
const historyList = el('#history-list');
const footFolder = el('#foot-folder') as HTMLButtonElement;
const footFormat = el('#foot-format') as HTMLButtonElement;
const footFolderLabel = el('#foot-folder-label');
const footFormatLabel = el('#foot-format-label');
const banner = el('#banner');

let lastUrl = '';
let lastState: AppViewState | null = null;
let probing = false;
let clearedForSavedId: string | null = null;

function el(sel: string): HTMLElement {
  const n = document.querySelector(sel);
  if (!(n instanceof HTMLElement)) throw new Error(`missing ${sel}`);
  return n;
}

function showBanner(text: string | null): void {
  if (!text) {
    banner.hidden = true;
    banner.textContent = '';
    return;
  }
  banner.hidden = false;
  banner.innerHTML = '';
  const item = document.createElement('div');
  item.className = 'banner-item banner-item--warn';
  item.textContent = text;
  banner.append(item);
}

function art(img: HTMLImageElement, url: string | null): void {
  img.onerror = () => {
    img.removeAttribute('src');
    img.hidden = true;
  };
  const src = thumbSrc(url);
  if (src) {
    img.hidden = false;
    img.src = src;
  } else {
    img.removeAttribute('src');
    img.hidden = true;
  }
}

function thumbSrc(url: string | null): string | null {
  if (!url) return null;
  const hostOnly = /^smthumb:\/\/([^/]+)\/?$/.exec(url);
  if (hostOnly?.[1] && hostOnly[1] !== 't') return `smthumb://t/${hostOnly[1]}`;
  return url;
}

const stage = el('#stage');

function setMid(name: 'none' | 'saved' | 'lookup' | 'confirm' | 'pulling' | 'error'): void {
  stage.dataset.mid = name;
  lookupView.hidden = name !== 'lookup';
  justSaved.hidden = name !== 'saved';
  confirm.hidden = name !== 'confirm';
  pulling.hidden = name !== 'pulling';
  landed.hidden = name !== 'error';
}

function setLookingUp(busy: boolean): void {
  probing = busy;
  lookupBtn.textContent = busy ? 'Looking up…' : 'Look up';
  lookupBtn.classList.toggle('is-working', busy);
  urlInput.setAttribute('aria-busy', busy ? 'true' : 'false');
  if (busy) setMid('lookup');
}

function recentTitle(job: JobView): string {
  if (job.sleeve?.title) return job.sleeve.title;
  const fromPath = job.outputPath ?? job.title;
  const base = fromPath.split('/').pop() ?? fromPath;
  return base.replace(/\s*\[[A-Za-z0-9_-]{11}\]\.[a-z0-9]+$/i, '') || job.title;
}

function bytesLabel(n: number | null): string {
  if (n === null || n <= 0) return '';
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(0)} KB`;
  return `${(n / (1024 * 1024)).toFixed(1)} MB`;
}

function paintMid(state: AppViewState): void {
  if (probing) {
    setMid('lookup');
    return;
  }
  const job = state.current;
  if (job?.phase === 'confirm' || job?.phase === 'probing') {
    setMid('confirm');
    const s = job.sleeve;
    sleeveTitle.textContent = s?.title ?? job.title;
    sleeveMeta.textContent = s?.durationLabel ?? '';
    mixNotice.hidden = !s?.mixNotice;
    art(sleeveArt, s?.thumbnailUrl ?? null);
    return;
  }
  if (job?.phase === 'running') {
    setMid('pulling');
    const s = job.sleeve;
    pullTitle.textContent = s?.title ?? job.title;
    pullLine.textContent = job.progressLine || 'Saving audio…';
    const pct = job.percent;
    if (pct === null || pct < 1) {
      pullBar.removeAttribute('value');
    } else {
      pullBar.value = pct;
    }
    art(pullArt, s?.thumbnailUrl ?? null);
    return;
  }
  if (job?.phase === 'error') {
    setMid('error');
    const s = job.sleeve;
    landTitle.textContent = s?.title ?? job.title;
    art(landArt, s?.thumbnailUrl ?? null);
    landOk.hidden = true;
    landErr.hidden = false;
    landError.hidden = false;
    landError.textContent = job.error ?? '';
    if (job.errorDetail) {
      landDetails.hidden = false;
      landDetailText.textContent = job.errorDetail;
    } else {
      landDetails.hidden = true;
    }
    landLine.textContent = '';
    return;
  }
  const saved = state.lastSaved;
  if (saved) {
    setMid('saved');
    savedTitle.textContent = recentTitle(saved);
    const size = bytesLabel(saved.bytes);
    savedMeta.textContent = [size, saved.folderLabel].filter(Boolean).join(' · ');
    art(savedArt, saved.sleeve?.thumbnailUrl ?? null);
    if (clearedForSavedId !== saved.id) {
      urlInput.value = '';
      lastUrl = '';
      clearedForSavedId = saved.id;
    }
    return;
  }
  setMid('none');
}

function paintHistory(items: JobView[]): void {
  historyList.replaceChildren();
  const seen = new Set<string>();
  const unique: JobView[] = [];
  for (const job of items.filter((j) => j.phase === 'ok')) {
    const key = job.sleeve?.videoId ?? job.url ?? job.id;
    if (seen.has(key)) continue;
    seen.add(key);
    unique.push(job);
  }
  for (const job of unique.slice(0, 12)) {
    const li = document.createElement('li');
    const img = document.createElement('img');
    img.alt = '';
    if (job.sleeve?.thumbnailUrl) {
      const src = thumbSrc(job.sleeve.thumbnailUrl);
      if (src) img.src = src;
      img.onerror = () => {
        img.removeAttribute('src');
      };
    }
    const col = document.createElement('div');
    col.className = 'sleeves__copy';
    const t = document.createElement('div');
    t.className = 'sleeves__title';
    t.textContent = recentTitle(job);
    const m = document.createElement('div');
    m.className = 'sleeves__meta';
    m.textContent = [job.sleeve?.durationLabel, job.folderLabel].filter(Boolean).join(' · ');
    col.append(t, m);
    const remove = document.createElement('button');
    remove.type = 'button';
    remove.className = 'sleeves__remove';
    remove.setAttribute('aria-label', `Remove ${recentTitle(job)} from Recent`);
    remove.textContent = '×';
    remove.addEventListener('click', (e) => {
      e.stopPropagation();
      void api.removeRecent(job.id).then(() => api.getState()).then(paintState);
    });
    li.append(img, col, remove);
    if (job.outputPath) {
      li.style.cursor = 'pointer';
      li.addEventListener('click', () => {
        void api.showInFinder(job.outputPath!);
      });
    }
    historyList.append(li);
  }
}

function applyPalette(palette: UiPalette): void {
  document.documentElement.dataset.palette = palette;
  for (const btn of document.querySelectorAll<HTMLButtonElement>('.listen__swatch')) {
    const id = parsePalette(btn.dataset.palette);
    const on = id === palette;
    btn.setAttribute('aria-checked', on ? 'true' : 'false');
  }
}

function paintState(state: AppViewState): void {
  lastState = state;
  applyPalette(state.palette);
  footFolderLabel.textContent = `Saving to ${state.outputLabel}`;
  footFormatLabel.textContent = state.formatLabel;
  heroTitle.textContent = state.lastSaved ? 'Save another' : 'Drop a YouTube link';
  heroHint.hidden = Boolean(state.lastSaved);
  paintMid(state);
  paintHistory(state.history);
  showBanner(state.notice);
}

async function ingest(raw: string): Promise<void> {
  const text = raw.trim();
  if (!text || probing) return;
  urlInput.value = text;
  waitError.hidden = true;
  setLookingUp(true);
  try {
    const parsed = await api.parseUrl(text);
    if (!parsed.ok) {
      waitError.hidden = false;
      waitError.textContent = parsed.reason;
      setLookingUp(false);
      void api.getState().then(paintState);
      return;
    }
    lastUrl = parsed.canonical;
    if (
      lastState?.current?.url === parsed.canonical &&
      (lastState.current.phase === 'confirm' || lastState.current.phase === 'running')
    ) {
      setLookingUp(false);
      void api.getState().then(paintState);
      return;
    }
    const probed = await api.probe(parsed.canonical);
    if (!probed.ok) {
      waitError.hidden = false;
      waitError.textContent = probed.reason;
      setLookingUp(false);
      void api.getState().then(paintState);
      return;
    }
    setLookingUp(false);
    void api.getState().then(paintState);
  } finally {
    if (probing) setLookingUp(false);
  }
}

function nextFormat(cur: AudioFormat): AudioFormat {
  if (cur === 'm4a') return 'mp3';
  if (cur === 'mp3') return 'alac';
  return 'm4a';
}

void api.getState().then(paintState);
api.onJob(() => {
  void api.getState().then(paintState);
});
api.onNotice(showBanner);

el('#btn-pull').addEventListener('click', () => {
  if (!lastUrl && lastState?.current?.url) lastUrl = lastState.current.url;
  if (!lastUrl) return;
  void api.startJob({ url: lastUrl }).then((r) => {
    if (!r.ok) {
      waitError.hidden = false;
      waitError.textContent = r.reason;
    }
  });
});

el('#btn-dismiss').addEventListener('click', () => {
  void api.dismiss().then(() => api.getState()).then(paintState);
});

el('#btn-stop').addEventListener('click', () => {
  void api.cancelJob().then(() => api.dismiss()).then(() => api.getState()).then(paintState);
});

el('#btn-saved-play').addEventListener('click', () => {
  const p = lastState?.lastSaved?.outputPath;
  if (p) void api.play(p);
});

el('#btn-saved-finder').addEventListener('click', () => {
  const p = lastState?.lastSaved?.outputPath;
  if (p) void api.showInFinder(p);
});

el('#btn-play').addEventListener('click', () => {
  const p = lastState?.current?.outputPath;
  if (p) void api.play(p);
});

el('#btn-finder').addEventListener('click', () => {
  const p = lastState?.current?.outputPath;
  if (p) void api.showInFinder(p);
});

el('#btn-rename').addEventListener('click', () => {
  const p = lastState?.current?.outputPath;
  if (p) void api.rename(p).then(() => api.getState()).then(paintState);
});

el('#btn-retry').addEventListener('click', () => {
  const url = lastState?.current?.url ?? lastUrl;
  if (!url) return;
  lastUrl = url;
  void api.startJob({ url });
});

el('#btn-another').addEventListener('click', () => {
  void api.dismiss().then(() => api.getState()).then(paintState);
});

footFolder.addEventListener('click', () => {
  void api.chooseFolder().then(() => api.getState()).then(paintState);
});

footFormat.addEventListener('click', () => {
  const cur = lastState?.format ?? 'm4a';
  void api.setFormat(nextFormat(cur)).then(() => api.getState()).then(paintState);
});

el('#foot-palettes').addEventListener('click', (e) => {
  const t = e.target;
  if (!(t instanceof HTMLButtonElement) || !t.classList.contains('listen__swatch')) return;
  const palette = parsePalette(t.dataset.palette);
  applyPalette(palette);
  void api.setPalette(palette).then(() => api.getState()).then(paintState);
});

urlForm.addEventListener('submit', (e) => {
  e.preventDefault();
  void ingest(urlInput.value);
});

window.addEventListener('focus', () => {
  const phase = lastState?.current?.phase;
  if (phase && phase !== 'idle' && phase !== 'cancelled') return;
  if (lastState?.lastSaved && !lastState.current) return;
  void api.readClipboard().then((t) => {
    if (/youtu\.?be/i.test(t)) {
      urlInput.value = t.trim();
      void ingest(t);
    }
  });
});

window.addEventListener('paste', (e) => {
  const target = e.target;
  if (target instanceof HTMLInputElement || target instanceof HTMLTextAreaElement) return;
  const t = e.clipboardData?.getData('text/plain');
  if (t) {
    e.preventDefault();
    void ingest(t);
  }
});

document.body.addEventListener('dragover', (e) => {
  e.preventDefault();
  document.body.classList.add('listen-drag');
});
document.body.addEventListener('dragleave', () => {
  document.body.classList.remove('listen-drag');
});
document.body.addEventListener('drop', (e) => {
  e.preventDefault();
  document.body.classList.remove('listen-drag');
  const text = e.dataTransfer?.getData('text/uri-list') || e.dataTransfer?.getData('text/plain');
  if (text) void ingest(text);
});
