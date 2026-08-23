# StreamMagpie — distribution protocol

Canonical policy for how this project is published, **and the ship checklist**.
Identity constants live in [`AGENTS.md`](../AGENTS.md); the build configuration
that implements all of this is `packages/app/electron-builder.yml` and
`packages/app/build/entitlements.mac.plist`, both of which carry their traps in
comments rather than here.

Same model as Cast Gorilla: **MIT source on public GitHub, paid notarized DMG on
Gumroad only.** StreamMagpie bundles LGPL ffmpeg rather than a GPL one, and
yt-dlp is Unlicense, so the grant on our own code is MIT and nothing in the
payload forces it wider.

The app runs a Python extractor and a media encoder over URLs the buyer pastes,
entirely on their Mac. Public source is how that stays inspectable.

## Model

| What | Where | Cost |
|---|---|---|
| Source (main, renderer, engine, app) | Public GitHub, **MIT** | Free |
| Official macOS DMG (Developer ID signed, notarized, stapled) | **Gumroad only** | Paid |
| yt-dlp **wheel + signed `extractor-manifest.json`** | GitHub Releases | Free — extractor data, **not** the product |
| Self-build from source | Your machine | Free (you supply signing) |

Pay once, own forever. No subscription, no accounts, no cloud. The app converts
on the buyer's machine and has nothing to phone home about except the extractor
manifest, which is a signed JSON file and a wheel.

Sale terms for the paid build are [`EULA.md`](EULA.md), and that file is the
copy of record: paste it into the Gumroad listing rather than writing a second
version there that can drift.

Intended public repo:

```
https://github.com/jayintheday/streammagpie
```

Product page (not created yet):

```
YOUR_GUMROAD_PRODUCT_URL
```

Gumroad product ID `YOUR_GUMROAD_PRODUCT_ID`. **Do not upload a DMG until those
placeholders are a real product.** When they exist, record them here — this file
is where they are read from, and the `ship-gumroad` skill's Constants table is
the second copy that must move with it.

## Hard rules

1. **Never** attach the app DMG, an `.app` zip, or any product binary to a
   GitHub Release.

   ⚠ **The one carve-out, and it is narrow.** The **only** GitHub Release assets
   ever allowed are extractor-channel files:

   ```
   yt_dlp-*.whl
   extractor-manifest.json
   extractor-manifest.json.sig
   ```

   They are allowed because the app's **signed extractor auto-update reads
   them** — the manifest names a wheel and its sha256, the app verifies the
   signature, and the wheel lands in Application Support. That channel is
   extractor data with a delivery mechanism, not a build of the product. An
   asset that is not one of those three shapes does not go on a Release, and
   "it is only a helper binary" is not a fourth shape.

2. **Never** publish artefacts through public CI, a public CDN, or any channel
   that undercuts Gumroad. Source is public; **binaries** are not. The same
   carve-out and only that carve-out applies: the extractor wheel, the manifest
   and its `.sig` may be served publicly, because a customer's app has to be
   able to fetch them without credentials. The DMG never may.

3. **Allowed:** `git tag vX.Y.Z` for source milestones. Product tags may have
   **zero** release assets. Prefer a bare tag over a GitHub "Release" UI entry,
   on the grounds that the UI exists to have files uploaded to it. The
   `extractor-*` tags are the exception by rule 1 and carry only the three files
   named there.

4. `packages/app/electron-builder.yml` sets `publish: null`, so an accidental
   `electron-builder --publish` or a stray token cannot target GitHub.

5. **Notary and Apple credentials stay in the local keychain profile
   `streammagpie`** (team `29UYFH4USR`). Never commit Apple IDs, app-specific
   passwords, or API keys, and delete any plaintext password file the moment it
   has served its purpose. Check the profile without submitting anything:
   ```bash
   xcrun notarytool history --keychain-profile streammagpie
   ```

6. **Never commit real video titles, channel names, watch URLs, or a person's
   download history** — in documents, commit messages, test fixtures, issues, or
   a human-gate record. **Characteristics only**: duration band, container and
   codec, whether the extractor needed the JS runtime, output format, rough file
   size, elapsed time. A download history is a reading list. Anything specific
   goes in a gitignored `NOTES.local.md`.

   Where a document genuinely needs an example URL, use the canonical public
   test video id `jNQXAC9IVRw` and nothing else.

## Before the first ship, once

**Store the notary credentials.** They live in the local keychain profile
`streammagpie` and nowhere else — never in this repo, never in an environment
file that gets committed:

```bash
xcrun notarytool store-credentials streammagpie \
  --apple-id <apple-id> --team-id 29UYFH4USR
```

It prompts for an **app-specific password** (generated at appleid.apple.com),
not the account password. Check it later without submitting anything:

```bash
xcrun notarytool history --keychain-profile streammagpie
```

⚠ **The Apple ID that works is not the git-committer address.** That is the
obvious guess and it returns `401 Invalid credentials`, because an app-specific
password only ever authenticates against the account that generated it. A
sibling project lost time to this exact wrong guess.

**The profile now exists and resolves.** It was created on 2026-08-23 and then
used unattended, twice in the same run: once by electron-builder's inline app
notarization and once by `scripts/sign-dmg.sh` for the DMG.
`[verified: run 2026-08-23]` Which Apple ID it was created with is deliberately
recorded nowhere in this repo — that is hard rule 5, and it applies to this
paragraph too.

## Ship checklist (maintainer)

**This ran end to end for the first time on 2026-08-23** and produced a signed,
notarized, stapled `StreamMagpie-0.1.0-arm64.dmg`. `[verified: run 2026-08-23]`
The steps below are a record rather than an inheritance, and the two corrections
that run forced are folded in — see
[The first signed build](#the-first-signed-build--2026-08-23) for what it
settled and [What has not been proven](#what-has-not-been-proven) for what it
did not.

⚠ **That does not make any step below a formality. Every rebuild re-earns its
gates** — nothing signs, notarizes or staples by inheritance, two of the build's
stages fail open regardless of how the last build went, and the greps in step 4
and the verification set in the build skill are run again in full for every
artefact that goes to a customer.

1. **Vendor gates — all four payloads present and verified.** The bundle carries
   four independent payloads and `extraResources` **fails open** on every one of
   them, so a missing vendor directory produces a DMG that builds clean and is
   hollow:

   | Payload | Gate |
   |---|---|
   | `vendor/ffmpeg/arm64` | `ffmpeg` + `ffprobe` present; `./ffmpeg -version` runs, and its configuration line contains `--enable-libmp3lame` and **not** `--enable-gpl`; `otool -L` shows nothing outside `/usr/lib`, `/System/Library` and `@rpath`; `COPYING.LGPLv2.1` and `LICENSE.md` sit beside the binaries |
   | `vendor/python/arm64` | populated; `bin/python3 --version` runs |
   | `vendor/js` | the runtime `electron-builder.yml`'s `mac.binaries` names — `js/qjs` |
   | `vendor/ytdlp` | exactly one current `yt_dlp-*.whl` (plus the `yt_dlp.whl` floor copy) |

   `scripts/build-ffmpeg.sh`, `scripts/vendor-python.sh`, `scripts/vendor-js.sh`
   and `scripts/vendor-ytdlp.sh` populate the pieces that are missing.

   ⚠ **MP3 is a sold feature.** An ffmpeg vendored without `libmp3lame` produces
   an app where m4a works and MP3 silently fails at save time — on the customer's
   machine, after the download, which is the most expensive place for it to
   happen.

2. **Build the DMG** — [`.claude/skills/build-dmg`](../.claude/skills/build-dmg/SKILL.md)
   owns this leg in full. The command it runs:
   ```bash
   cd packages/app
   CSC_NAME="Intheday Ltd (29UYFH4USR)" APPLE_KEYCHAIN_PROFILE=streammagpie \
     npm run dist:dmg 2>&1 | tee /tmp/streammagpie-build.log
   ```
   ⚠ **`CSC_NAME` is how the signing identity reaches the build.**
   `electron-builder.yml` deliberately commits no `identity:` key, so an official
   build that forgets this variable signs with whatever Developer ID
   electron-builder auto-discovers — or, on a machine with none, produces an
   unsigned bundle and a `skipped macOS notarization` WARN.

   ⚠ **`npm run dist` builds NO DMG** — it is `electron-builder --dir`, the
   unpacked `.app` alone. `dist:dmg` is the one that produces the disk image.

   **Expect roughly nine minutes**, inline app notarization included: on
   2026-08-23 the app ran 13:47 to 13:56 and the DMG was written at 14:00.
   `[verified: run 2026-08-23]` Most of that is Apple's notary queue, so it is
   not a stable number; a run that finishes in two is the shape of one that
   skipped notarization, which is what step 4's first grep exists to catch. An
   expectation of twenty minutes carried over from a sibling project belongs to
   a larger payload, not this one.

3. **Sign the DMG, then notarize it, then staple it. In that order.**

   electron-builder signs the `.app`, **not the DMG around it**. Straight out of
   the build a sibling's DMG reported `code object is not signed at all` and
   `spctl` rejected it with `source=no usable signature`. This pass is required,
   not optional, and `scripts/sign-dmg.sh` is it:

   ```bash
   V=$(node -p "require('./packages/app/package.json').version")
   bash scripts/sign-dmg.sh "packages/app/release/StreamMagpie-$V-arm64.dmg"
   ```

   ⚠ **The order is load-bearing. Signing invalidates an existing ticket**, so a
   sequence that signs after stapling produces a file that passes every local
   check and fails on a clean Mac. Sign first, notarize what was signed, staple
   last. The script does exactly that and nothing else.

   ⚠ **The identity has two spellings and the tools disagree.** Raw `codesign`
   takes the **prefixed** form `Developer ID Application: Intheday Ltd
   (29UYFH4USR)`; `CSC_NAME` takes the **bare** qualifier `Intheday Ltd
   (29UYFH4USR)` and throws `Please remove prefix "Developer ID Application:"`
   if given the other. Each fails unhelpfully on the other's form.

   ⚠ If notarization returns `HTTP 403 - A required agreement is missing or has
   expired` while the certificate is still valid: certificate validity says
   nothing about **account** validity, and agreements are per-team. Accept it in
   the developer portal with the team switcher set to Intheday Ltd.

4. **Grep the build log. Three greps, and they are the whole point of this
   step.** Two of the build's stages **fail open** — they print a line at WARN
   and carry on, producing an artefact that looks finished and is not:

   | Expect | In the log | What it means if wrong |
   |---|---|---|
   | 0 occurrences | `skipped macOS notarization` | no credentials were found; Gatekeeper will refuse the app on a clean Mac |
   | 0 occurrences | `file source doesn't exist` | a vendor payload is missing; the app fails on the customer's first conversion |
   | 1 occurrence | `notarization successful` | — |

   **The build exits 0 either way.** The exit code will not tell you.

   ```bash
   grep -c "skipped macOS notarization" /tmp/streammagpie-build.log   # want 0
   grep -c "file source doesn't exist"  /tmp/streammagpie-build.log   # want 0
   grep -c "notarization successful"    /tmp/streammagpie-build.log   # want 1
   ```

   ⚠ `extractor-manifest` fetch failures in the app's own runtime log are a
   different thing entirely and are **normal** until the first wheel release
   exists. They are not a ship blocker and they are not one of these three greps.

5. **Human gate.** A person installs this exact DMG into `/Applications`, launches
   it, pastes a URL, and saves **both** an m4a and an MP3 that then play. A log
   cannot answer any of that. The `ship-gumroad` skill blocks on it and asks what
   was on screen; the answer is recorded back into this file as characteristics
   only, per hard rule 6. **This gate has not been cleared for 0.1.0.**

   ⚠ **While the quarantine attribute is present, macOS runs the app under App
   Translocation, and this looks exactly like a path bug.** The app executes from
   a randomized read-only
   `/private/var/folders/.../AppTranslocation/<uuid>/d/StreamMagpie.app` — not
   from `/Applications`, whatever the installer just did. It launched and ran
   fine from there on 2026-08-23. `[verified: launching 2026-08-23]` The cost is
   diagnostic: `process.resourcesPath` points inside the translocated copy, so
   anybody chasing a missing payload sees a path nobody installed to and doubts
   the install rather than the symptom. `xattr -cr` on the installed bundle
   clears the attribute and the app then runs from `/Applications` proper, with
   the signature intact — `codesign --verify --strict` still passes afterwards.
   `[verified: run 2026-08-23]` Clear it to debug; do not clear it to make a
   Gatekeeper check pass, because that is the check.

6. **Upload to Gumroad** — [`.claude/skills/ship-gumroad`](../.claude/skills/ship-gumroad/SKILL.md)
   owns this leg. It refuses to run while `YOUR_GUMROAD_PRODUCT_ID` and
   `YOUR_GUMROAD_PRODUCT_URL` are still placeholders, which today they are.

7. **Tag the source.** `git tag v$V`, **zero** release assets (hard rule 3).

## What ships inside the DMG

`StreamMagpie.app`, and inside it four vendored payloads that the app resolves
through `process.resourcesPath` — there is no PATH fallback in a packaged build,
so a payload that did not make it into the bundle fails on the customer's first
conversion rather than silently working on the machine of everyone who could
have caught it. Step 4's second grep is the earlier warning for the same fault.

```
release/mac-arm64/StreamMagpie.app/Contents/
├── Info.plist                    co.streammagpie.app · version from packages/app/package.json
├── MacOS/StreamMagpie
├── Frameworks/                   Electron 43.4.0
└── Resources/
    ├── app.asar                  dist/{main,preload,renderer} + @streammagpie/engine
    ├── icon.icns                 the app icon
    ├── ffmpeg/                   ffmpeg, ffprobe (static LGPL, libmp3lame)
    │                             + COPYING.LGPLv2.1, LICENSE.md
    ├── python/                   CPython 3.12.14 (bin/python3, lib/, lib-dynload/)
    │                             + its own LICENSE
    ├── js/                       qjs — the JS runtime yt-dlp uses for n-sig
    └── ytdlp/                    yt_dlp-*.whl (+ yt_dlp.whl floor copy)
                                  + the wheel's own licence inside it
```

⚠ **The LGPL licence files are not decoration.** `vendor/ffmpeg/arm64` is copied
unfiltered, licences included, and that is the compliance mechanism: ship
`COPYING.LGPLv2.1` and `LICENSE.md` next to the binaries, and record the
corresponding-source tarball URL in that folder's README. A build that drops
them is a licence violation, not a cosmetic miss.

`electron-builder.yml`'s `mac.binaries` names four loose Mach-Os —
`ffmpeg/ffmpeg`, `ffmpeg/ffprobe`, `js/qjs`, `python/bin/python3` — and what it
guarantees is that those four are signed **with the entitlements**, by name.

⚠ **It is not the only thing that signs, and this document used to say it was.**
electron-builder 26.15.3 handles the list first — `signing additional
user-defined binaries` in the log — and then makes a **separate recursive pass**
over the finished bundle, `signing file=release/mac-arm64/StreamMagpie.app`. All
**14** Mach-O images in the shipped app carry `Authority=Developer ID
Application: Intheday Ltd (29UYFH4USR)`, `TeamIdentifier=29UYFH4USR` and
`flags=0x10000(runtime)`: the four on the list, and the ten under
`Contents/Resources/python/lib/` the list never names.
`[verified: run 2026-08-23]`

Do **not** delete `mac.binaries` on the strength of that. It is what pins the
entitlements onto those four by name, and whether removing it would change any
of the 14 signatures has not been tested. `[inferred]`

## The first signed build — 2026-08-23

The first ever signed, notarized and stapled StreamMagpie artefact. Everything in
this section is `[verified: run 2026-08-23]` unless it says otherwise, and it is
one artefact on one machine on one day — not a proven pipeline.

Environment: electron-builder 26.15.3, Electron 43.4.0, macOS 26.5 (25F71),
Xcode 26.3, notarytool 1.1.0, Node v24.15.0. The gate was green first
(`npx tsc -b`, `npm run typecheck -w packages/app`, 19/19 vitest) and
`npm run vendor:verify` passed all four payload gates.

| | |
|---|---|
| Artifact | `packages/app/release/StreamMagpie-0.1.0-arm64.dmg`, **173,500,067 bytes** (165 MB) |
| Build | `CSC_NAME="Intheday Ltd (29UYFH4USR)" APPLE_KEYCHAIN_PROFILE=streammagpie npm run dist:dmg`, exit 0 |
| Wall clock | roughly **9 minutes** end to end, inline app notarization included (app 13:47 to 13:56, DMG written 14:00) |
| The three greps | `skipped macOS notarization` **0**, `file source doesn't exist` **0**, `notarization successful` **1** |
| The `.app` | `Identifier=co.streammagpie.app`, `flags=0x10000(runtime)`, `Notarization Ticket=stapled`; `codesign --verify --deep --strict` reports "valid on disk" and "satisfies its Designated Requirement" |
| DMG notary submission | `b3b32e8f-778d-4e50-80b9-1ad3f5f37023`, status **Accepted** |
| DMG after stapling | `xcrun stapler validate` passes; `spctl -a -t open --context context:primary-signature` returns `accepted / source=Notarized Developer ID` |
| Icon digest, from the shipped bundle | `4862602c66d1d0eaddd3c55ad4f96de4551e62d6a6c0930aa0e60afa7d2ca553` — matches the constant |
| Payload, read from the mounted app | ffmpeg 9.0.1, configuration carries `--enable-libmp3lame` and none of `gpl`, `nonfree` or `version3`; `otool -L` returns zero non-system lines for both `ffmpeg` and `ffprobe`; the licence files are present; Python 3.12.14; `qjs` present and executable; both wheels present |

The entitlements plist was handed to a real `codesign` for the first time, on a
throwaway probe, before any of the above: exit 0 and silent, and
`codesign -d --entitlements -` then showed exactly the two keys, allow-jit and
allow-unsigned-executable-memory. **No AMFI double-hyphen fault.** That trap is
not retired by one pass — it is a property of whatever comment text the file
carries today, so it is re-earned on every edit.

**Gatekeeper, from a simulated download.** A locally built DMG carries no
quarantine bit, so one was written by hand:
`xattr -w com.apple.quarantine "0081;00000000;Safari;"`. Gatekeeper still
returned `accepted / source=Notarized Developer ID`. Installed into
`/Applications` the attribute propagated as `0281;00000000;;`, and
`spctl -a -vvv -t exec` returned `accepted / source=Notarized Developer ID /
origin=Developer ID Application: Intheday Ltd (29UYFH4USR)`. The app launched
and stayed alive — gpu-process, network service and renderer helpers all spawned,
no instant SIGKILL. `[verified: launching 2026-08-23]` It ran under App
Translocation while quarantined; see step 5 of the ship checklist, which is where
that will cost somebody an afternoon.

**Two conversions, characteristics only** (hard rule 6), both produced through
the signed bundle's own python, yt-dlp and ffmpeg, on the canonical public test
id `jNQXAC9IVRw`:

| Format | Codec | Rate | Channels | Duration | Size | Wall clock |
|---|---|---|---|---|---|---|
| m4a | aac | 48000 Hz | 2 | 19.005542 s | 410,228 bytes | ~3 s |
| mp3 | mp3 | 48000 Hz | 2 | 19.005542 s | 120,620 bytes | ~3 s |

⚠ **Both ran through the bundled toolchain directly, not through the app's UI.**
They prove the payload converts. They do not prove the product does.

## What has not been proven

Kept honest and deliberately short. The packaging chain is now proven once; what
follows is what a green build did not touch, and it is the half that matters to a
buyer.

- **The app's own GUI flow has never been exercised.** No URL has been pasted
  into the running app, no sleeve preview has been seen, nothing has been saved
  through the UI, and no save-location TCC prompt has been answered. The two
  conversions above went through python3, yt-dlp and ffmpeg invoked from the
  signed bundle — **not** through the renderer and IPC that a customer uses. The
  human gate at step 5 is outstanding, and it is with the maintainer.
- **Nothing has been checked on a clean Mac, or with networking off.** Both
  `spctl` and `stapler validate` fall back to an **online** ticket lookup, so
  every pass recorded above proves **notarized**; none of them conclusively
  proves **stapled**. A Mac that has never seen this developer, offline, is the
  only thing that settles that.
- ⚠ **ALAC is BROKEN, and it fails silently.** Selecting it produces an
  **AAC** file with an `.m4a` extension — lossy, and byte-for-byte the kind of
  file the m4a option already gives you. `[verified: run 2026-08-23]` The cause
  is upstream, not ours: `packages/engine/src/argv.ts` builds the correct
  `-x --audio-format alac`, and yt-dlp's own table has
  `'alac': ('m4a', None, ('-acodec', 'alac'))` — but in
  `yt_dlp/postprocessor/ffmpeg.py`, `FFmpegExtractAudioPP.run()` then does
  `more_opts = self._quality_args(acodec)`, which **replaces** rather than
  extends. Because alac's encoder entry is `None` (not `'copy'`), that branch is
  taken and the `-acodec alac` pair is discarded. The command that finally runs
  is `ffmpeg -vn -movflags +faststart out.m4a`, and ffmpeg defaults the m4a
  container to AAC. The bundled ffmpeg is **not** at fault: it carries both
  `alac` and `alac_at` encoders and produces real ALAC when asked directly.
  A working invocation adds `--postprocessor-args "ExtractAudio:-acodec alac"`,
  which yields `codec_name=alac`, `bits_per_raw_sample=24`, 2,441,748 bytes for
  the same 19.006 s source that the broken path renders in 310,517 bytes — the
  size gap is the tell. **This must be fixed before ALAC is sold as lossless.**
- **Nothing has been rebuilt.** One green build is not a reproducible one, and
  the vendor payloads it consumed are gitignored downloads rather than tracked
  inputs.
- **No customer has ever received anything**, because the Gumroad product does
  not exist.

### The two risk hypotheses — both disproven `[verified: run 2026-08-23]`

This section used to carry two `[inferred]` hypotheses about what the first
signed build would hit. Both were wrong, and both were wrong for the same
underlying reason: **this repo asserted in three places that electron-builder
signs only the loose files `mac.binaries` names and does not walk a directory of
extra resources.** For electron-builder 26.15.3 that is false. It signs the named
list first, then makes a separate recursive pass over the finished `.app`, and
all 14 Mach-Os in the bundle came out on our Team ID with the hardened runtime
set. The corrected statement now lives in
[What ships inside the DMG](#what-ships-inside-the-dmg),
`packages/app/electron-builder.yml` and
`packages/app/build/entitlements.mac.plist`.

**(a) The CPython payload's nested Mach-Os are not walked — no.** The notary
service never got the chance to be lenient, and that mechanism is the finding
rather than the pass itself: there were no unsigned nested Mach-Os in the
submission, because electron-builder's recursive pass had already signed every
one of them with our Developer ID under the hardened runtime. The proposed
deep-sign pass over `Contents/Resources/python` is work electron-builder already
does.

The payload description that hypothesis rested on was also wrong in scale. It
said "every C extension under `lib/python3.12/lib-dynload/*.so`", implying many.
This python-build-standalone tree carries **three** `.so` files — `_crypt`,
`_dbm`, `_tkinter` — plus **seven** dylibs (`libpython3.12`, `libtcl9.0`,
`libtcl9tk9.0`, `libitcl4.3.8`, `libtcl9itcl4.3.8`, `libthread3.0.6`,
`libtcl9thread3.0.6`): **ten** nested Mach-Os in total. Most extensions,
`_ssl`, `_socket`, `_hashlib` and `binascii` among them, are statically linked
into `libpython3.12.dylib` and are not separate files at all.

**(b) Hardened-runtime library validation versus CPython's `dlopen` — no**, and
this was tested directly rather than inferred from (a). From the app installed in
`/Applications`, under the hardened runtime it shipped with:
`python3 --version` gives Python 3.12.14, exit 0;
`python3 -c 'import ssl, zlib, ctypes, sqlite3, hashlib, bz2, lzma, socket,
binascii'` reports all C extensions imported OK, exit 0; and `import yt_dlp` off
the floor wheel loads yt-dlp 2026.08.19, exit 0. That import **is** the `dlopen`
operation library validation governs. No SIGKILL, and no empty log.

So `com.apple.security.cs.disable-library-validation` is **not needed and stays
absent**. `packages/app/build/entitlements.mac.plist` records it as a settled
absence with this evidence, and still argues against adding it speculatively:
with it set, any dylib can be loaded into the process. Read that file before
adding any key.

⚠ **Keep the symptom on record even though it did not happen.** If library
validation ever does reject an extension module, the extractor dies by **instant
SIGKILL** the moment a conversion starts — no dialog, no error, nothing in any
log. **An empty log is the signature of that failure**, which is exactly what
gets it misdiagnosed as a path bug. A payload change can reintroduce it.

## Customer updates

Two channels, and they are not the same thing.

**The app** — until an in-app updater exists (deferred, `docs/DEFERRED.md`):

- Upload each new DMG as a **new file version** on the same Gumroad product.
- Buyers re-download from their Gumroad library.
- Optionally email customers that a new version is available.

Do **not** wire `electron-updater` to a public GitHub Releases feed. That would
serve the paid build for free and break hard rules 1 and 2 in one line of config.

**The extractor** — yt-dlp updates arrive silently, as a wheel into Application
Support, gated by the signed `extractor-manifest.json`. That channel is public by
design (hard rule 1's carve-out) and ships no part of the app.

## Trademark

**StreamMagpie** — the name and the app icon — identifies the official product.
The MIT license grants rights to the *software*; it does **not** grant rights to
ship a third-party build as StreamMagpie.

## Build from source (free)

See the root `README.md`. An unsigned local `.app` is fine for hacking; it is not
a substitute for the Gumroad DMG on a clean Mac. A contributor with no Developer
ID certificate sets:

```bash
CSC_IDENTITY_AUTO_DISCOVERY=false npm run dist:dmg -w packages/app
```

which produces an unsigned, un-notarized disk image. Gatekeeper will refuse it on
any Mac but the one that built it, and that is the correct outcome.

## Landing page

The official marketing CTA must link **Gumroad**, not GitHub Releases, once the
product exists. The wording matches the README's "Official builds" section — one
sentence about MIT source being free, one about the official signed build being
sold on Gumroad only — so a reader who arrives from either direction is told the
same thing.
