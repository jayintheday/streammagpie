import { defineConfig } from 'vite';
import { resolve } from 'node:path';
import { ELECTRON_NODE_TARGET } from './build/app-version.js';

const root = import.meta.dirname;

export default defineConfig({
  build: {
    outDir: resolve(root, 'dist/preload'),
    emptyOutDir: true,
    target: ELECTRON_NODE_TARGET,
    minify: false,
    sourcemap: true,
    lib: {
      entry: resolve(root, 'src/preload/index.ts'),
      formats: ['cjs'],
      fileName: () => 'index.cjs',
    },
    rollupOptions: {
      external: ['electron'],
    },
  },
});
