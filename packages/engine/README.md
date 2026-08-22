# Engine

Wraps **yt-dlp** as a subprocess. Do not write an InnerTube client.

## JS runtime (Stage 0)

Default argv uses `--js-runtimes` when a path is supplied.

- Prefer **qjs** if n-sig works and downloads are not throttled to ~50 KB/s.
- Fall back to **Deno ≥ 2.3** if qjs fails EJS or throttles.

Record the measured winner here after a live spike:

- Date:
- Video:
- qjs result:
- Deno result:
- Shipped runtime:

Never ship the official `yt-dlp_macos` PyInstaller binary (GPL combined work). Use a wheel on python-build-standalone.
