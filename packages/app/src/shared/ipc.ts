export const REQ = {
  parseUrl: 'sm:parseUrl',
  probe: 'sm:probe',
  chooseFolder: 'sm:chooseFolder',
  getState: 'sm:getState',
  startJob: 'sm:startJob',
  cancelJob: 'sm:cancelJob',
  setFormat: 'sm:setFormat',
  setPalette: 'sm:setPalette',
  about: 'sm:about',
  checkExtractor: 'sm:checkExtractor',
  play: 'sm:play',
  showInFinder: 'sm:showInFinder',
  rename: 'sm:rename',
  readClipboard: 'sm:readClipboard',
  dismiss: 'sm:dismiss',
  removeRecent: 'sm:removeRecent',
} as const;

export const EVT = {
  job: 'sm:job',
  notice: 'sm:notice',
} as const;

export type AudioFormat = 'm4a' | 'mp3' | 'alac';

export const PALETTE_IDS = [
  'coral',
  'midnight',
  'deep-ocean',
  'lavender-haze',
  'sunset-dreams',
] as const;

export type UiPalette = (typeof PALETTE_IDS)[number];

export const PALETTE_LABELS: Record<UiPalette, string> = {
  coral: 'Coral',
  midnight: 'Midnight',
  'deep-ocean': 'Deep Ocean',
  'lavender-haze': 'Lavender Haze',
  'sunset-dreams': 'Sunset Dreams',
};

export const PALETTE_WINDOW_BG: Record<UiPalette, string> = {
  coral: '#1a1714',
  midnight: '#0d1117',
  'deep-ocean': '#050e1a',
  'lavender-haze': '#16131e',
  'sunset-dreams': '#1e1318',
};

export function parsePalette(raw: unknown): UiPalette {
  if (typeof raw === 'string' && (PALETTE_IDS as readonly string[]).includes(raw)) {
    return raw as UiPalette;
  }
  return 'coral';
}

export type JobPhase = 'idle' | 'probing' | 'confirm' | 'running' | 'ok' | 'error' | 'cancelled';

export type Sleeve = {
  title: string;
  durationSec: number | null;
  durationLabel: string;
  thumbnailUrl: string | null;
  mixNotice: boolean;
  videoId: string | null;
};

export type JobView = {
  id: string;
  url: string;
  title: string;
  format: AudioFormat;
  phase: JobPhase;
  percent: number | null;
  speed: string | null;
  eta: string | null;
  progressLine: string;
  error: string | null;
  errorDetail: string | null;
  outputPath: string | null;
  bytes: number | null;
  folderLabel: string | null;
  finishedAt: number | null;
  sleeve: Sleeve | null;
};

export type AppViewState = {
  outputDir: string | null;
  outputLabel: string;
  format: AudioFormat;
  formatLabel: string;
  palette: UiPalette;
  current: JobView | null;
  lastSaved: JobView | null;
  history: JobView[];
  notice: string | null;
  extractorVersion: string | null;
};

export type ProbeResult =
  | { ok: true; canonical: string; mixNotice: boolean; sleeve: Sleeve }
  | { ok: false; reason: string };

export type StartJobParams = { url: string };

export type AboutInfo = {
  version: string;
  chrome: string;
  extractorVersion: string | null;
};

export type EventChannel = (typeof EVT)[keyof typeof EVT];

export type StreamMagpieApi = {
  parseUrl: (
    url: string,
  ) => Promise<{ ok: true; canonical: string; mixNotice: boolean } | { ok: false; reason: string }>;
  probe: (url: string) => Promise<ProbeResult>;
  chooseFolder: () => Promise<string | null>;
  getState: () => Promise<AppViewState>;
  startJob: (params: StartJobParams) => Promise<{ ok: true } | { ok: false; reason: string }>;
  cancelJob: () => Promise<void>;
  dismiss: () => Promise<void>;
  removeRecent: (jobId: string) => Promise<void>;
  setFormat: (format: AudioFormat) => Promise<void>;
  setPalette: (palette: UiPalette) => Promise<void>;
  about: () => Promise<AboutInfo>;
  checkExtractor: () => Promise<void>;
  play: (filePath: string) => Promise<void>;
  showInFinder: (filePath: string) => Promise<void>;
  rename: (filePath: string) => Promise<string | null>;
  readClipboard: () => Promise<string>;
  onJob: (cb: (job: JobView | null) => void) => () => void;
  onNotice: (cb: (notice: string | null) => void) => () => void;
};
