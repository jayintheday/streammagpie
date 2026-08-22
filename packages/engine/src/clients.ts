/** InnerTube client fallback. Remote manifest may overwrite this list. */

export const DEFAULT_CLIENT_CHAIN = [
  'visionos',
  'tv',
  'web_embedded',
  'android_vr',
] as const;

export type YoutubeClient = (typeof DEFAULT_CLIENT_CHAIN)[number] | string;

export function playerClientArg(chain: readonly string[]): string {
  return `youtube:player_client=${chain.join(',')}`;
}

export function isDeadWebOnly(client: string): boolean {
  return client.trim().toLowerCase() === 'web';
}
