import { createHash } from 'node:crypto';
import { mkdir, readFile, rename, rm, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { DEFAULT_CLIENT_CHAIN } from './clients.js';

export type ExtractorManifest = {
  ytdlp_version: string;
  wheel_url: string;
  sha256: string;
  client_chain: string[];
  extractor_args?: Record<string, unknown>;
  notice: string | null;
};

export function parseManifest(json: unknown): ExtractorManifest {
  if (typeof json !== 'object' || json === null) {
    throw new Error('Extractor manifest is not an object.');
  }
  const o = json as Record<string, unknown>;
  if (typeof o.ytdlp_version !== 'string' || o.ytdlp_version === '') {
    throw new Error('Manifest missing ytdlp_version.');
  }
  if (typeof o.wheel_url !== 'string' || !o.wheel_url.startsWith('https://')) {
    throw new Error('Manifest wheel_url must be an https URL.');
  }
  if (typeof o.sha256 !== 'string' || !/^[a-f0-9]{64}$/i.test(o.sha256)) {
    throw new Error('Manifest sha256 must be 64 hex chars.');
  }
  const chain = Array.isArray(o.client_chain)
    ? o.client_chain.filter((c): c is string => typeof c === 'string' && c.length > 0)
    : [...DEFAULT_CLIENT_CHAIN];
  if (chain.length === 0) {
    throw new Error('Manifest client_chain is empty.');
  }
  const notice = o.notice === null || o.notice === undefined ? null : String(o.notice);
  return {
    ytdlp_version: o.ytdlp_version,
    wheel_url: o.wheel_url,
    sha256: o.sha256.toLowerCase(),
    client_chain: chain,
    extractor_args:
      typeof o.extractor_args === 'object' && o.extractor_args !== null
        ? (o.extractor_args as Record<string, unknown>)
        : {},
    notice,
  };
}

export function sha256Hex(bytes: Buffer): string {
  return createHash('sha256').update(bytes).digest('hex');
}

export function verifyWheel(bytes: Buffer, expectedSha256: string): void {
  const got = sha256Hex(bytes);
  if (got !== expectedSha256.toLowerCase()) {
    throw new Error(`Wheel sha256 mismatch: expected ${expectedSha256}, got ${got}.`);
  }
}

/**
 * Minisign-style detached signature is verified by the app with a pinned pubkey.
 * This helper only checks that a signature blob is present and non-empty;
 * cryptographic verify lives in the app so the engine stays free of sodium.
 */
export function requireSignature(sig: string | undefined | null): string {
  if (!sig || sig.trim() === '') {
    throw new Error('Extractor manifest has no signature. Refusing to apply it.');
  }
  return sig.trim();
}

export async function atomicWriteFile(target: string, bytes: Buffer): Promise<void> {
  const dir = path.dirname(target);
  await mkdir(dir, { recursive: true });
  const tmp = `${target}.${process.pid}.tmp`;
  await writeFile(tmp, bytes);
  await rename(tmp, target);
}

export async function swapWheel(opts: {
  liveDir: string;
  previousDir: string;
  wheelName: string;
  bytes: Buffer;
}): Promise<void> {
  const live = path.join(opts.liveDir, opts.wheelName);
  const prev = path.join(opts.previousDir, opts.wheelName);
  await mkdir(opts.liveDir, { recursive: true });
  await mkdir(opts.previousDir, { recursive: true });
  try {
    const current = await readFile(live);
    await atomicWriteFile(prev, current);
  } catch {
    /* no previous */
  }
  await atomicWriteFile(live, opts.bytes);
}

export async function rollbackWheel(opts: {
  liveDir: string;
  previousDir: string;
  wheelName: string;
}): Promise<boolean> {
  const live = path.join(opts.liveDir, opts.wheelName);
  const prev = path.join(opts.previousDir, opts.wheelName);
  try {
    const bytes = await readFile(prev);
    await atomicWriteFile(live, bytes);
    await rm(prev, { force: true });
    return true;
  } catch {
    return false;
  }
}
