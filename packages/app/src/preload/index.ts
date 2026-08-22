import { contextBridge, ipcRenderer } from 'electron';
import type { IpcRendererEvent } from 'electron';
import { EVT, REQ } from '../shared/ipc.js';
import type {
  AudioFormat,
  EventChannel,
  JobView,
  StartJobParams,
  StreamMagpieApi,
  UiPalette,
} from '../shared/ipc.js';

function subscribe<T>(channel: EventChannel, cb: (payload: T) => void): () => void {
  const listener = (_event: IpcRendererEvent, payload: T): void => cb(payload);
  ipcRenderer.on(channel, listener as (e: IpcRendererEvent, ...a: unknown[]) => void);
  return () =>
    ipcRenderer.removeListener(
      channel,
      listener as (e: IpcRendererEvent, ...a: unknown[]) => void,
    );
}

const api: StreamMagpieApi = {
  parseUrl: (url: string) => ipcRenderer.invoke(REQ.parseUrl, url),
  probe: (url: string) => ipcRenderer.invoke(REQ.probe, url),
  chooseFolder: () => ipcRenderer.invoke(REQ.chooseFolder),
  getState: () => ipcRenderer.invoke(REQ.getState),
  startJob: (params: StartJobParams) => ipcRenderer.invoke(REQ.startJob, params),
  cancelJob: () => ipcRenderer.invoke(REQ.cancelJob),
  dismiss: () => ipcRenderer.invoke(REQ.dismiss),
  removeRecent: (jobId: string) => ipcRenderer.invoke(REQ.removeRecent, jobId),
  setFormat: (format: AudioFormat) => ipcRenderer.invoke(REQ.setFormat, format),
  setPalette: (palette: UiPalette) => ipcRenderer.invoke(REQ.setPalette, palette),
  about: () => ipcRenderer.invoke(REQ.about),
  checkExtractor: () => ipcRenderer.invoke(REQ.checkExtractor),
  play: (filePath: string) => ipcRenderer.invoke(REQ.play, filePath),
  showInFinder: (filePath: string) => ipcRenderer.invoke(REQ.showInFinder, filePath),
  rename: (filePath: string) => ipcRenderer.invoke(REQ.rename, filePath),
  readClipboard: () => ipcRenderer.invoke(REQ.readClipboard),
  onJob: (cb: (job: JobView | null) => void) => subscribe(EVT.job, cb),
  onNotice: (cb: (notice: string | null) => void) => subscribe(EVT.notice, cb),
};

contextBridge.exposeInMainWorld('streammagpie', api);
