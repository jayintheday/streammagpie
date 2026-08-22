# Deferred (Stage 4)

Not in the first shippable audio MVP:

- Playlists, channel batch, multi-item queue. Mix URLs (`list=` plus a video id) save **this track** only.
- Chapter split / embed chapters / thumbnails (yt-dlp flags exist; UI later)
- `--cookies-from-browser` and WKWebView sign-in
- PO-token provider plugins
- Video download
- In-app **app** binary updater (Sparkle / private appcast). Gumroad re-download stays the app channel until then.

## The reliability ladder

Three of the deferred items above are rungs on a ladder, and the ladder is why they
are deferred rather than missing. Extraction failures are overwhelmingly a
server-side judgement about the *client*, not a missing flag, and a desktop app
running on a residential connection at human request rates already sits near the
top of that judgement. So the mitigations are ordered cheapest-first, and we stop
as soon as the failures stop:

1. **Do nothing.** Default client chain, the user's own connection. Ships.
2. **Polite pacing.** One download at a time, `--sleep-interval`, no concurrency.
   Cheap insurance that keeps ordinary use off any heuristic. Ships.
3. **Client fallback chain.** Retry across `visionos` → `tv` → `web_embedded` →
   `android_vr`. Ships — and the chain is **remote config**, carried in the signed
   extractor manifest, so it can be reordered without a new DMG.
4. **Optional cookie import** (`--cookies-from-browser`). Opt-in. Deferred.
5. **Optional sign-in** via a one-time WKWebView login. Deferred.
6. **PO-token provider.** Last resort; the JS runtime is already bundled, so the
   marginal cost is low. Deferred.

Rungs 4–6 are deferred on scope, not refused: each one adds a credential path and a
consent question that the first release does not need in order to work.

**Proxy rotation, IP cycling and fingerprint randomisation are not on this ladder
and never join it.** They are refused, not deferred — they turn a grey-area
consumer utility into something built for evasion, and rungs 1–5 already cover the
realistic failure modes.
