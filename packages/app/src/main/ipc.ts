import { ipcMain } from 'electron';
import { EVT, REQ } from '../shared/ipc.js';
import type { AudioFormat, StartJobParams, UiPalette } from '../shared/ipc.js';
import type { ExtractorHost } from './extractor-host.js';

export function attachIpc(host: ExtractorHost): void {
  ipcMain.handle(REQ.parseUrl, (_e, url: string) => host.parseUrl(url));
  ipcMain.handle(REQ.probe, (_e, url: string) => host.probe(url));
  ipcMain.handle(REQ.chooseFolder, () => host.chooseFolder());
  ipcMain.handle(REQ.getState, () => host.getState());
  ipcMain.handle(REQ.startJob, (_e, params: StartJobParams) => host.startJob(params));
  ipcMain.handle(REQ.cancelJob, () => {
    host.cancelJob();
  });
  ipcMain.handle(REQ.dismiss, () => {
    host.dismiss();
  });
  ipcMain.handle(REQ.removeRecent, (_e, jobId: string) => host.removeRecent(jobId));
  ipcMain.handle(REQ.setFormat, (_e, format: AudioFormat) => host.setFormat(format));
  ipcMain.handle(REQ.setPalette, (_e, palette: UiPalette) => host.setPalette(palette));
  ipcMain.handle(REQ.about, () => ({
    version: __APP_VERSION__,
    chrome: process.versions.chrome,
    extractorVersion: host.aboutPayload().extractorVersion,
  }));
  ipcMain.handle(REQ.checkExtractor, () => host.checkExtractor());
  ipcMain.handle(REQ.play, (_e, filePath: string) => host.play(filePath));
  ipcMain.handle(REQ.showInFinder, (_e, filePath: string) => host.showInFinder(filePath));
  ipcMain.handle(REQ.rename, (_e, filePath: string) => host.rename(filePath));
  ipcMain.handle(REQ.readClipboard, () => host.readClipboard());
  void EVT;
}
