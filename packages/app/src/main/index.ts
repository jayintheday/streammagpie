import './helper-paths.js';

import { app, BrowserWindow, Menu, dialog, net, protocol, shell } from 'electron';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { existsSync } from 'node:fs';
import path from 'node:path';
import { ExtractorHost, thumbFile } from './extractor-host.js';
import { attachIpc } from './ipc.js';

protocol.registerSchemesAsPrivileged([
  {
    scheme: 'smthumb',
    privileges: { standard: true, secure: true, supportFetchAPI: true, corsEnabled: true },
  },
]);

const dirname =
  typeof __dirname !== 'undefined' ? __dirname : path.dirname(fileURLToPath(import.meta.url));

const DEV_SERVER_URL = process.env.VITE_DEV_SERVER_URL;
const host = new ExtractorHost();

async function createWindow(): Promise<void> {
  const win = new BrowserWindow({
    width: 720,
    height: 680,
    minWidth: 560,
    minHeight: 480,
    backgroundColor: host.windowBackground(),
    titleBarStyle: 'hiddenInset',
    trafficLightPosition: { x: 16, y: 14 },
    title: 'StreamMagpie',
    webPreferences: {
      preload: path.join(dirname, '../preload/index.cjs'),
      contextIsolation: true,
      sandbox: true,
      nodeIntegration: false,
    },
  });

  host.attach(win);

  win.webContents.setWindowOpenHandler(({ url }) => {
    void shell.openExternal(url);
    return { action: 'deny' };
  });

  win.webContents.on('will-navigate', (event, url) => {
    const current = win.webContents.getURL();
    if (url !== current) event.preventDefault();
  });

  if (DEV_SERVER_URL) {
    await win.loadURL(DEV_SERVER_URL);
  } else {
    await win.loadFile(path.join(dirname, '../renderer/index.html'));
  }
}

function installMenu(): void {
  const isMac = process.platform === 'darwin';
  const template: Electron.MenuItemConstructorOptions[] = [
    ...(isMac
      ? [
          {
            label: app.name,
            submenu: [
              {
                label: 'About StreamMagpie',
                click: () => {
                  void showAbout();
                },
              },
              { type: 'separator' },
              {
                label: 'Check extractor…',
                click: () => {
                  void host.checkExtractor().then(() => showAbout());
                },
              },
              { type: 'separator' },
              { role: 'hide' },
              { role: 'hideOthers' },
              { role: 'unhide' },
              { type: 'separator' },
              { role: 'quit' },
            ],
          } satisfies Electron.MenuItemConstructorOptions,
        ]
      : []),
    { role: 'fileMenu' },
    { role: 'editMenu' },
    { role: 'viewMenu' },
    { role: 'windowMenu' },
    {
      role: 'help',
      submenu: [
        {
          label: 'About StreamMagpie',
          click: () => {
            void showAbout();
          },
        },
      ],
    },
  ];
  Menu.setApplicationMenu(Menu.buildFromTemplate(template));
}

async function showAbout(): Promise<void> {
  const state = host.getState();
  const extractor = state.extractorVersion ? `yt-dlp ${state.extractorVersion}` : 'bundled / PATH';
  const extra = state.notice ? `\n\n${state.notice}` : '';
  await dialog.showMessageBox({
    type: 'info',
    title: 'About StreamMagpie',
    message: 'StreamMagpie',
    detail: `App ${__APP_VERSION__}\nExtractor: ${extractor}${extra}`,
  });
}

app.whenReady().then(async () => {
  protocol.handle('smthumb', (request) => {
    const u = new URL(request.url);
    const fromPath = decodeURIComponent(u.pathname.replace(/^\//, '')).replace(/\.jpg$/, '');
    const fromHost = u.hostname && u.hostname !== 't' ? u.hostname : '';
    const id = fromPath || fromHost;
    if (!/^[A-Za-z0-9_-]{11}$/.test(id)) {
      return new Response('not found', { status: 404 });
    }
    const file = thumbFile(id);
    if (!existsSync(file)) return new Response('not found', { status: 404 });
    return net.fetch(pathToFileURL(file).href);
  });
  attachIpc(host);
  await host.boot();
  installMenu();
  await createWindow();
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});

app.on('activate', () => {
  if (BrowserWindow.getAllWindows().length === 0) void createWindow();
});
