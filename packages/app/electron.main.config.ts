import { defineConfig } from 'vite';
import { resolve } from 'node:path';
import { builtinModules } from 'node:module';
import { readAppVersion, ELECTRON_NODE_TARGET } from './build/app-version.js';

const root = import.meta.dirname;
const version = readAppVersion(resolve(root, 'package.json'));
const nodeExternals = [...builtinModules, ...builtinModules.map((m) => `node:${m}`)];

export default defineConfig({
  define: {
    __APP_VERSION__: JSON.stringify(version),
  },
  build: {
    outDir: resolve(root, 'dist/main'),
    emptyOutDir: true,
    target: ELECTRON_NODE_TARGET,
    minify: false,
    sourcemap: true,
    lib: {
      entry: resolve(root, 'src/main/index.ts'),
      formats: ['cjs'],
      fileName: () => 'index.cjs',
    },
    rollupOptions: {
      external: ['electron', ...nodeExternals],
    },
  },
});
