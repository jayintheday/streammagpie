/**
 * dev.mjs — the dev loop orchestrator for the StreamMagpie app.
 *
 * 1. Builds the workspace with `tsc -b` (see the box below — load-bearing).
 * 2. Bundles the Electron main + preload (Vite lib builds).
 * 3. Starts the Vite dev server for the renderer (HMR).
 * 4. Launches Electron pointed at the dev-server URL via VITE_DEV_SERVER_URL.
 *
 * ┌──────────────────────────────────────────────────────────────────────────┐
 * │  ⚠ THE ENGINE'S `dist/` IS AN INPUT TO STEP 2, AND IT IS GITIGNORED.     │
 * │                                                                          │
 * │  `electron.main.config.ts` BUNDLES `@streammagpie/engine` (it says why), │
 * │  which means Rollup reads `packages/engine/dist/index.js` — a build      │
 * │  product of the root `tsc -b`, not a tracked file. Two consequences      │
 * │  worth knowing before they cost an afternoon:                            │
 * │                                                                          │
 * │    · a FRESH CLONE must run `npx tsc -b` before `npm run dev`, or this   │
 * │      build fails with a module-not-found for a package that is plainly   │
 * │      right there in node_modules;                                        │
 * │    · a STALE `dist/` bundles stale engine code SILENTLY. If the engine   │
 * │      is being changed alongside the app, `npx tsc -b` is part of the dev │
 * │      loop rather than part of the gate.                                  │
 * │                                                                          │
 * │  So this script runs it. It is two seconds when nothing changed, and the │
 * │  alternative is a class of "I fixed that already" that has no symptom    │
 * │  other than being wrong.                                                 │
 * └──────────────────────────────────────────────────────────────────────────┘
 *
 * ⚠ THE SIDECARS ARE NOT BUNDLED IN DEV. `helper-paths.ts` sets the
 * STREAMMAGPIE_* tool paths only when `app.isPackaged`, so a dev run resolves
 * python3 / ffmpeg / qjs / the yt-dlp wheel through `resolve-tools.ts`, which
 * falls back to `vendor/` and then to whatever is on PATH. A checkout that has
 * never run `scripts/vendor-*.sh` and has no yt-dlp installed fails loudly at
 * the first conversion with a message naming the script to run — it does not
 * silently degrade.
 *
 * GUI launch is best-effort — a headless or sandboxed environment may not open
 * a window.
 */

import { spawn } from 'node:child_process';
import { build, createServer } from 'vite';
import electronPath from 'electron';

/** Run a command to completion, inheriting stdio. Rejects on a non-zero exit. */
function run(command, args) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, { stdio: 'inherit' });
    child.on('error', reject);
    child.on('close', (code) =>
      code === 0 ? resolve() : reject(new Error(`${command} ${args.join(' ')} exited ${code}`)),
    );
  });
}

async function main() {
  // The engine's dist. See the box above — this is not belt-and-braces, it is
  // the difference between bundling the engine that exists and the engine that
  // existed last time somebody remembered.
  await run('npx', ['tsc', '-b', '../..']);

  await build({ configFile: 'electron.main.config.ts' });
  await build({ configFile: 'electron.preload.config.ts' });

  const server = await createServer({ configFile: 'vite.config.ts' });
  await server.listen();

  const url = server.resolvedUrls?.local?.[0];
  if (!url) throw new Error('Vite dev server did not report a URL');
  server.printUrls();

  const child = spawn(electronPath, ['dist/main/index.cjs'], {
    stdio: 'inherit',
    env: { ...process.env, VITE_DEV_SERVER_URL: url },
  });

  const shutdown = async () => {
    await server.close();
    process.exit(0);
  };
  child.on('close', shutdown);
  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
