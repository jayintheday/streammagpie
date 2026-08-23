# StreamMagpie

On-device YouTube → audio for macOS. Paste a URL, get an m4a (or MP3 / ALAC).

Everything runs on your Mac: a bundled yt-dlp, a bundled CPython, a bundled
static LGPL ffmpeg and a bundled JS runtime. Nothing is uploaded, and there is
no account. A sibling app alongside Cast Gorilla.

## Official builds

Source is **MIT** and free to clone, build, and modify.

The official macOS app — **StreamMagpie**, Developer ID signed, notarized, with
bundled LGPL ffmpeg — is sold on **Gumroad only**. We do **not** publish DMGs or
other binaries on GitHub Releases.

- Buy / download: <https://6185821221924.gumroad.com/l/streammagpie> — listing
  is set up but not yet published; nothing is for sale there yet.
- Distribution rules: [docs/DISTRIBUTION.md](docs/DISTRIBUTION.md)

Updates for customers are new Gumroad file versions (re-download from your
library). There is no in-app auto-updater.

**One carve-out, and it is the only one:** extractor-channel files —
`yt_dlp-*.whl`, `extractor-manifest.json` and its `.sig` — may be published on
GitHub Releases, because the app's signed extractor auto-update reads them. That
is extractor data, not the product. The app DMG never goes there. Same wording,
same rule, in [docs/DISTRIBUTION.md](docs/DISTRIBUTION.md).

## Dev

```bash
npm install
npx tsc -b
npm test
npm run dev
```

Needs Python 3, ffmpeg, and a JS runtime (`qjs` or `deno`) on PATH until you
vendor them:

```bash
bash scripts/vendor-ytdlp.sh
bash scripts/vendor-js.sh
# optional packaged helpers:
bash scripts/build-ffmpeg.sh
bash scripts/vendor-python.sh
```

## Legal

YouTube's terms generally forbid downloading. Use this for content you have the
right to copy. Not for App Store distribution (guideline 5.2.3). See
[docs/EULA.md](docs/EULA.md) and [docs/DISTRIBUTION.md](docs/DISTRIBUTION.md).
