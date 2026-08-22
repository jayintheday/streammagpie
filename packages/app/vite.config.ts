import { defineConfig } from 'vite';
import { resolve } from 'node:path';
import { readAppVersion, ELECTRON_CHROME_TARGET } from './build/app-version.js';

const root = import.meta.dirname;
const version = readAppVersion(resolve(root, 'package.json'));

export default defineConfig({
  root: resolve(root, 'src/renderer'),
  base: './',
  define: {
    __APP_VERSION__: JSON.stringify(version),
  },
  build: {
    outDir: resolve(root, 'dist/renderer'),
    emptyOutDir: true,
    target: ELECTRON_CHROME_TARGET,
    sourcemap: true,
  },
  server: {
    port: 5288,
    strictPort: true,
  },
  clearScreen: false,
});
