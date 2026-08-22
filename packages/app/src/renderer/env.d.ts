import type { StreamMagpieApi } from '../shared/ipc.js';

declare global {
  interface Window {
    streammagpie: StreamMagpieApi;
  }
}

export {};
