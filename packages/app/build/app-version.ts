/**
 * app-version.ts — the single source of the app version, read at build time.
 *
 * Imported by BOTH Vite configs that need it (`vite.config.ts` for the
 * renderer, `electron.main.config.ts` for `app:about`), so the two cannot
 * substitute different strings into the same constant.
 *
 * `packages/app/package.json`'s `version` is what electron-builder writes into
 * `CFBundleShortVersionString`, `CFBundleVersion` and the DMG filename, so
 * neither process may carry its own copy — both READ it from that file and
 * receive it as `__APP_VERSION__` (declared in `src/env.d.ts`).
 *
 * ⚠ FATAL ON A MALFORMED VERSION, NEVER A FALLBACK. A default here would ship a
 * plausible-looking but wrong version silently, which is the entire failure
 * this exists to remove: a stale fallback here is exactly what a broken bundle
 * would quietly ship, with the About window, the bundle plist and the DMG
 * filename each free to disagree and nothing to notice it. `'0.0.0'` would be
 * the worst possible choice of default, since it is also the placeholder in
 * the monorepo root's package.json. Stopping the build is the only honest
 * outcome.
 *
 * Read + `JSON.parse` rather than `import pkg from './package.json'`: these
 * configs are executed by Node after an esbuild transform, and a plain
 * `readFileSync` needs no import attributes, no bundler JSON plugin, and no
 * assumptions about how the config itself was loaded.
 */

import { readFileSync } from 'node:fs';

export function readAppVersion(pkgPath: string): string {
  // `readFileSync` already throws on a missing or unreadable file, so the only
  // case left to handle is a file that parses but has no usable `version`.
  const pkg: unknown = JSON.parse(readFileSync(pkgPath, 'utf8'));
  const version =
    typeof pkg === 'object' && pkg !== null && 'version' in pkg
      ? (pkg as { version: unknown }).version
      : undefined;

  // Deliberately NOT `String(version)`: that would turn a missing field into
  // the literal "undefined" and ship it as the version.
  if (typeof version !== 'string' || version.trim() === '') {
    throw new Error(
      `${pkgPath} has no usable "version" (found ${JSON.stringify(version)}). ` +
        `That field is the single source of truth for the app version: it feeds ` +
        `CFBundleShortVersionString, CFBundleVersion and the DMG filename via ` +
        `electron-builder, and the version shown in the app via __APP_VERSION__. ` +
        `Set it to a version string, e.g. "0.1.0".`,
    );
  }
  return version;
}

/**
 * The esbuild/Rollup target for everything that runs inside Electron.
 *
 * ⚠ `chrome150` IS MEASURED, NOT ASSUMED [verified: run]. This package's own
 * Electron 43.4.0 reports `process.versions.chrome === '150.0.7871.224'`:
 *
 *     ELECTRON_RUN_AS_NODE=1 <electron> -e "console.log(process.versions.chrome)"
 *
 * ⚠ AND IT IS WORTH MEASURING RATHER THAN LOOKING UP. A remembered or
 * copied-forward Chromium number is the kind of mistake that survives
 * indefinitely, because an UNDER-stated target costs nothing but unnecessary
 * downlevelling — there is no failure to notice, so nobody ever checks. Bump
 * Electron and this constant goes stale in exactly the same silent way. The
 * command above takes a second and settles it.
 *
 * `app:about` reports the runtime's own `process.versions.chrome`, so a build
 * that ever disagreed with this constant would say so in the window rather than
 * in a comment.
 */
export const ELECTRON_CHROME_TARGET = 'chrome150';

/**
 * The Node target for the main and preload bundles.
 *
 * Electron 43.4.0 embeds Node 24.18.1 [verified: run, same command as above].
 * `node20` is a deliberate conservative floor rather than a match: nothing in
 * this codebase uses a Node 22-or-24-only syntax feature, and an OVER-stated
 * Node target is the one that produces a bundle the runtime cannot parse — a
 * failure that appears as a blank window with a syntax error in a log nobody is
 * tailing. Under-stating costs a little unnecessary downlevelling and nothing
 * else.
 */
export const ELECTRON_NODE_TARGET = 'node20';
