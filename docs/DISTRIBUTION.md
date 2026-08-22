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

## Ship checklist (maintainer)

⚠ **None of this has been run.** Nothing below is observed; every step is
inherited from a sibling that got it working, and the first StreamMagpie build
will discover which parts of the inheritance do not transfer. See
[What has not been proven](#what-has-not-been-proven) before believing any step
is a formality. **Every rebuild re-earns its gates** — nothing signs, notarizes
or staples by inheritance, two of the build's stages fail open, and the greps in
step 4 and the verification set in the build skill are run again in full for
every artefact that goes to a customer.

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
   only, per hard rule 6.

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
    ├── python/                   CPython 3 (bin/python3, lib/, lib-dynload/)
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
`ffmpeg/ffmpeg`, `ffmpeg/ffprobe`, `js/qjs`, `python/bin/python3` — and those are
the four that get signed. **That list is exactly as long as it looks.**

## What has not been proven

Kept honest and deliberately short. **Nothing here is proven. Not one item.**

- **The app has never been built for release.** `npm run dist:dmg` has not been
  run. No DMG exists.
- **Nothing has ever been signed.** The `streammagpie` keychain profile may not
  exist yet on this machine, and `packages/app/build/entitlements.mac.plist` has
  never been handed to a real `codesign`.
- **Nothing has ever been notarized or stapled.** No submission has been made.
- **The packaged app has never been launched.** No conversion has run through the
  bundled ffmpeg, the bundled CPython, the bundled qjs or the bundled wheel via
  `process.resourcesPath`. Paths are asserted by test; a test is not a launch.
- **No customer has ever received anything**, because the Gumroad product does
  not exist.

### Two risk hypotheses for the first signed build `[inferred]`

Both are reasoned from the payload layout, not observed. They are recorded here
so the first build's failure is diagnosed rather than guessed at, and so nobody
widens the entitlements pre-emptively to make a symptom go away.

**(a) The CPython payload's nested Mach-Os are not walked.**
`mac.binaries` lists `Contents/Resources/python/bin/python3` and nothing else
under `python/`. A python-build-standalone tree also carries **many** Mach-O
files that are not that binary: every C extension under `lib/python3.12/
lib-dynload/*.so`, plus `lib/libpython3.12.dylib`. electron-builder signs the
loose files `mac.binaries` names; it does **not** walk a directory of extra
resources hunting for Mach-Os the way it walks a nested `.app` bundle. An
unsigned nested Mach-O is a documented notarization rejection.

*Likely fix:* a **deep-sign pass over the whole `python` tree** before the DMG is
built — find every Mach-O under `Contents/Resources/python`, sign each with the
Developer ID, hardened runtime and the same entitlements, innermost first. That
is also the fix that makes hypothesis (b) moot, because it puts the entire tree
on our own Team ID.

*Symptom if unaddressed:* `notarytool` returns Invalid, and the submission log
names specific `.so` paths as "not signed with a valid Developer ID
certificate".

**(b) Hardened-runtime library validation versus CPython's `dlopen`.**
Library validation requires that code loaded into a process be signed by the same
Team ID as the process, or by Apple. CPython's whole extension mechanism is
`dlopen` on the `lib-dynload/*.so` files at import time. **If the deep-sign pass
in (a) happens, this resolves itself** — same team, so both branches of the rule
are satisfied and no exception is needed. If it does not, or if a payload arrives
pre-signed by somebody else's team, the build may need
`com.apple.security.cs.disable-library-validation` in
`packages/app/build/entitlements.mac.plist`.

⚠ **That key is a real widening and it is not the first thing to try.** Establish
*what* got rejected first. The deep-sign pass is the narrower fix and should be
exhausted before the entitlement is considered.

*Symptom if this is the cause:* the packaged app dies by **instant SIGKILL** the
moment Python starts — no dialog, no error, nothing in any log. **An empty log is
the signature of this failure**, which is exactly what makes it get misdiagnosed
as a path bug.

Both hypotheses are cross-referenced from
`packages/app/build/entitlements.mac.plist`, which is the file that would carry
the fix for (b) and which records why each absent entitlement is absent. Read it
before adding a key.

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
