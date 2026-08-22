import { net } from 'electron';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { verify as verifyEd25519 } from 'node:crypto';
import path from 'node:path';
import {
  parseManifest,
  rollbackWheel,
  swapWheel,
  verifyWheel,
  type ExtractorManifest,
} from '@streammagpie/engine';
import { supportDir } from './helper-paths.js';

/** Ed25519 public key (raw 32-byte, base64). Empty means do not apply remote wheels. */
export const EXTRACTOR_PUBKEY_B64 = process.env.STREAMMAGPIE_EXTRACTOR_PUBKEY ?? '';

const MANIFEST_URL =
  process.env.STREAMMAGPIE_MANIFEST_URL ??
  'https://github.com/jayintheday/streammagpie/releases/latest/download/extractor-manifest.json';

type SignedEnvelope = {
  manifest?: unknown;
  signature?: string;
};

export async function fetchText(url: string): Promise<string> {
  const res = await net.fetch(url);
  if (!res.ok) throw new Error(`HTTP ${res.status} fetching ${url}`);
  return await res.text();
}

export async function fetchBytes(url: string): Promise<Buffer> {
  const res = await net.fetch(url);
  if (!res.ok) throw new Error(`HTTP ${res.status} fetching ${url}`);
  return Buffer.from(await res.arrayBuffer());
}

function createEd25519Spki(raw32: Buffer): Buffer {
  const prefix = Buffer.from('302a300506032b6570032100', 'hex');
  return Buffer.concat([prefix, raw32]);
}

export function verifyManifestSignature(body: string, signatureB64: string, pubkeyB64: string): void {
  const key = Buffer.from(pubkeyB64, 'base64');
  const sig = Buffer.from(signatureB64, 'base64');
  const ok = verifyEd25519(
    null,
    Buffer.from(body, 'utf8'),
    { key: createEd25519Spki(key), format: 'der', type: 'spki' },
    sig,
  );
  if (!ok) throw new Error('Extractor manifest signature failed.');
}

export async function checkAndApplyExtractor(): Promise<{
  manifest: ExtractorManifest | null;
  applied: boolean;
  notice: string | null;
}> {
  const dir = supportDir();
  await mkdir(dir, { recursive: true });

  // Fetch AND parse inside the same guard. A 200 with a body that is not a JSON
  // object — a captive portal login page, a proxy error page — is a failure to
  // reach the manifest, exactly like a dead network, and degrades to the same
  // quiet no-op. Only a body we could actually read gets past here, so every
  // throw below this point is a deliberate refusal worth surfacing.
  let envelope: SignedEnvelope & Record<string, unknown>;
  try {
    const raw = await fetchText(MANIFEST_URL);
    const parsed: unknown = JSON.parse(raw);
    if (typeof parsed !== 'object' || parsed === null || Array.isArray(parsed)) {
      throw new Error('Extractor manifest body is not a JSON object.');
    }
    envelope = parsed as SignedEnvelope & Record<string, unknown>;
  } catch {
    return { manifest: null, applied: false, notice: null };
  }

  const innerObject = envelope.manifest !== undefined ? envelope.manifest : envelope;
  const inner = JSON.stringify(innerObject);
  const sig = envelope.signature;

  if (!EXTRACTOR_PUBKEY_B64) {
    return { manifest: null, applied: false, notice: null };
  }
  if (!sig || sig.trim() === '') {
    throw new Error('Extractor manifest has no signature. Refusing to apply it.');
  }
  verifyManifestSignature(inner, sig, EXTRACTOR_PUBKEY_B64);

  const manifest = parseManifest(innerObject);

  const liveMeta = path.join(dir, 'applied-version.txt');
  let current = '';
  try {
    current = (await readFile(liveMeta, 'utf8')).trim();
  } catch {
    current = '';
  }
  if (current === manifest.ytdlp_version) {
    return { manifest, applied: false, notice: manifest.notice };
  }

  const bytes = await fetchBytes(manifest.wheel_url);
  verifyWheel(bytes, manifest.sha256);
  await swapWheel({
    liveDir: path.join(dir, 'live'),
    previousDir: path.join(dir, 'previous'),
    wheelName: 'yt_dlp.whl',
    bytes,
  });
  await writeFile(liveMeta, `${manifest.ytdlp_version}\n`, 'utf8');
  await writeFile(path.join(dir, 'client_chain.json'), JSON.stringify(manifest.client_chain), 'utf8');
  return { manifest, applied: true, notice: manifest.notice };
}

export async function rollbackExtractor(): Promise<boolean> {
  const dir = supportDir();
  return rollbackWheel({
    liveDir: path.join(dir, 'live'),
    previousDir: path.join(dir, 'previous'),
    wheelName: 'yt_dlp.whl',
  });
}

export async function loadClientChain(): Promise<string[] | null> {
  try {
    const raw = await readFile(path.join(supportDir(), 'client_chain.json'), 'utf8');
    const parsed: unknown = JSON.parse(raw);
    if (Array.isArray(parsed) && parsed.every((x) => typeof x === 'string')) {
      return parsed;
    }
  } catch {
    /* floor */
  }
  return null;
}
