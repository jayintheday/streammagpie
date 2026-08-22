import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { resolve } from 'node:path';
import { parsePalette } from '../src/shared/ipc.js';

describe('packaging contracts', () => {
  it('keeps appId co.streammagpie.app', () => {
    const yml = readFileSync(resolve(import.meta.dirname, '../electron-builder.yml'), 'utf8');
    expect(yml).toMatch(/appId: co\.streammagpie\.app/);
    expect(yml).toMatch(/publish: null/);
  });

  it('entitlements comments above plist have no double hyphen', () => {
    const raw = readFileSync(resolve(import.meta.dirname, '../build/entitlements.mac.plist'), 'utf8');
    const above = raw.split('</plist>')[0] ?? '';
    expect(above.includes(' --')).toBe(false);
  });
});

describe('parsePalette', () => {
  it('keeps known palettes and falls back to coral', () => {
    expect(parsePalette('midnight')).toBe('midnight');
    expect(parsePalette('deep-ocean')).toBe('deep-ocean');
    expect(parsePalette('nope')).toBe('coral');
    expect(parsePalette(undefined)).toBe('coral');
  });
});
