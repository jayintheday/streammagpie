---
name: build-dmg
description: Build, sign, notarize and staple the official StreamMagpie release DMG, then verify it. Use when the user says "build the DMG", "run the DMG pipeline", "make the release build", "prepare the release DMG", or after a version bump when an artifact is needed. Runs the vendor payload gates, `npm run dist:dmg`, the three fail-open build-log greps, the `scripts/sign-dmg.sh` sign to notarize to staple pass, and the full verification set. Never uploads.
---

# build-dmg

Build leg of a StreamMagpie release: turns a clean tree into a **signed,
notarized, stapled and verified** `.dmg`.

**Out of scope: uploading.** This skill never calls `gumroad`, never tags, never
pushes. The upload leg is [`.claude/skills/ship-gumroad`](../ship-gumroad/SKILL.md),
and it re-runs its own gates against whatever this one produces — as it should,
since the two legs can be separated by days.

The policy behind every step is `docs/DISTRIBUTION.md`. **This pipeline ran end
to end for the first time on 2026-08-23 and produced a signed, notarized,
stapled `StreamMagpie-0.1.0-arm64.dmg`** — notary submission
`b3b32e8f-778d-4e50-80b9-1ad3f5f37023`, Accepted. `[verified: run 2026-08-23]`
So the steps below are a record, not a plan.

⚠ **That is one artefact, not a proven pipeline.** Two stages fail open and the
exit code does not tell you; nothing signs, notarizes or staples by inheritance;
and every gate here is re-earned per build. Read
`docs/DISTRIBUTION.md` → "What has not been proven" before reporting anything as
finished — in particular the app's own GUI flow has never been exercised, and
nothing has been checked on a clean Mac.

## Constants

| | |
|---|---|
| Artifact | `packages/app/release/StreamMagpie-$V-arm64.dmg` |
| Version source | `packages/app/package.json` (single source of truth) |
| `CSC_NAME` (bare qualifier) | `Intheday Ltd (29UYFH4USR)` |
| Keychain profile | `streammagpie` |
| Build log | `/tmp/streammagpie-build.log` |
| Retired placeholder icon digest | `6ee152c8a54a0859e6d84d3ecd20d0a71564272b59c0656ccc9607550686b7b0` |
| Current icon digest (build/icon.icns) | `4862602c66d1d0eaddd3c55ad4f96de4551e62d6a6c0930aa0e60afa7d2ca553` |

⚠ **THE IDENTITY HAS TWO SPELLINGS AND THE TOOLS DISAGREE — THIS IS THE
INVERSION.** `CSC_NAME` takes the **bare** qualifier exactly as in the table
above; give it the prefixed form and electron-builder throws
`Please remove prefix "Developer ID Application:"`. Raw `codesign` — inside
`scripts/sign-dmg.sh` — wants the **prefixed** form,
`Developer ID Application: Intheday Ltd (29UYFH4USR)`. **Never write the prefixed
form as `CSC_NAME`.** Each tool fails unhelpfully on the other's spelling, and
the failure does not name the reason.

## Step 1 — Preconditions

1. **Clean tree.** `git status --porcelain` comes back empty. A release built
   from a dirty tree cannot be reproduced from the tag that names it.

2. **Confirm the version is the intended one.** Ask; do not assume a bump
   happened or did not.
   ```bash
   V=$(node -p "require('./packages/app/package.json').version")
   echo "building $V"
   ```

3. **The four vendor payload gates.** ⚠ `extraResources` **fails open** on every
   one of them: a missing directory produces a build that exits 0 and a DMG that
   is hollow. Check all four before building, not after.

   | Payload | Gate | Populate with |
   |---|---|---|
   | `vendor/ffmpeg/arm64` | `ffmpeg` and `ffprobe` present and executable; `./ffmpeg -version` runs; its **configuration line contains `--enable-libmp3lame`** and **not** `--enable-gpl`; `COPYING.LGPLv2.1` and `LICENSE.md` sit beside them | `bash scripts/build-ffmpeg.sh` |
   | `vendor/python/arm64` | populated; `bin/python3 --version` runs | `bash scripts/vendor-python.sh` |
   | `vendor/js` | holds the runtime `electron-builder.yml`'s `mac.binaries` names — `js/qjs` | `bash scripts/vendor-js.sh` |
   | `vendor/ytdlp` | **exactly one** current `yt_dlp-*.whl` (plus the `yt_dlp.whl` floor copy) | `bash scripts/vendor-ytdlp.sh` |

   ```bash
   ls -l vendor/ffmpeg/arm64/{ffmpeg,ffprobe,COPYING.LGPLv2.1,LICENSE.md}
   ./vendor/ffmpeg/arm64/ffmpeg -version | head -1
   ./vendor/ffmpeg/arm64/ffmpeg -version | grep -- "--enable-libmp3lame"   # want a match
   ./vendor/python/arm64/bin/python3 --version
   ls -l vendor/js/qjs
   ls vendor/ytdlp/yt_dlp-*.whl
   ```

   ⚠ **MP3 is a sold feature and this grep is the only cheap place to catch it.**
   An ffmpeg without `libmp3lame` gives an app where m4a works and MP3 fails at
   save time — on the customer's machine, after the download. Every other gate in
   the pipeline passes.

   ⚠ **More than one `yt_dlp-*.whl` in `vendor/ytdlp` is a stop, not a warning.**
   The whole directory is copied into the bundle, so a stale wheel ships beside
   the current one and which one loads is not something the build decides.

   ⚠ **`vendor/js` must hold the runtime the yml signs.** `vendor-js.sh` builds
   the pinned QuickJS and refuses to substitute anything else — a runtime that
   `mac.binaries` does not name would ship **unsigned** and fail notarization
   (a vendored `deno` is the documented example; the script explains what a
   deliberate switch requires). If the yml has genuinely moved to a different
   runtime, match the yml.

4. **The keychain profile exists.** Checks without submitting anything:
   ```bash
   xcrun notarytool history --keychain-profile streammagpie
   ```
   It was created on 2026-08-23 and resolved unattended for both the inline app
   notarization and the DMG pass in the same run. `[verified: run 2026-08-23]`
   If it does not exist on the machine you are on, stop and run the one-time
   `store-credentials` step in `docs/DISTRIBUTION.md` → "Before the first ship,
   once". ⚠ The Apple ID that works is **not** the git-committer address, and it
   is not written down in this repo anywhere — ask.

## Step 2 — Build

```bash
cd packages/app
CSC_NAME="Intheday Ltd (29UYFH4USR)" APPLE_KEYCHAIN_PROFILE=streammagpie \
  npm run dist:dmg 2>&1 | tee /tmp/streammagpie-build.log
```

⚠ **`npm run dist` builds NO DMG.** It is `electron-builder --dir` — the unpacked
`.app` alone. `dist:dmg` is the one that produces the disk image, and the two
names are one character apart.

⚠ **`CSC_NAME` is how the signing identity reaches the build.**
`electron-builder.yml` deliberately commits no `identity:` key. An official build
that forgets the variable signs with whatever Developer ID electron-builder
auto-discovers — or, on a machine with none, produces an unsigned bundle and a
`skipped macOS notarization` WARN, exit code 0.

**Expect roughly nine minutes**, inline app notarization included: on 2026-08-23
the app ran 13:47 to 13:56 and the DMG was written at 14:00.
`[verified: run 2026-08-23]` Most of that is Apple's notary queue, so it is not a
stable number — but a run that finishes in two minutes has the shape of one that
skipped notarization, which is what step 3's first grep catches. An expectation
of twenty minutes carried over from a sibling project belongs to a bigger
payload, not this one.

The `tee` is not optional: step 3 has nothing to read without it.

## Step 3 — Grep the log

**Three greps, and they are the only net under two stages that fail open.** Both
failure strings are printed at WARN and the build carries on, producing an
artefact that looks finished and is not.

| Expect | In the log | What it means if wrong |
|---|---|---|
| 0 occurrences | `skipped macOS notarization` | no credentials were found; the build is a dud and Gatekeeper will refuse it on a clean Mac |
| 0 occurrences | `file source doesn't exist` | a vendor directory was empty; the DMG shipped hollow and the app fails on the customer's first conversion |
| 1 occurrence | `notarization successful` | — |

```bash
grep -c "skipped macOS notarization" /tmp/streammagpie-build.log   # want 0
grep -c "file source doesn't exist"  /tmp/streammagpie-build.log   # want 0
grep -c "notarization successful"    /tmp/streammagpie-build.log   # want 1
```

⚠ **The build exits 0 either way. The exit code will not tell you.** If a grep is
off target, stop here — the fix is upstream (credentials, or a vendor payload),
and signing a hollow DMG in step 4 only makes it a properly notarized hollow DMG.

## Step 4 — Sign, then notarize, then staple

electron-builder signs the `.app`, **not the DMG around it**. Straight out of the
build a sibling project's DMG reported `code object is not signed at all`, and
`spctl` rejected it with `source=no usable signature`. This pass is required:

```bash
cd "$(git rev-parse --show-toplevel)"
V=$(node -p "require('./packages/app/package.json').version")
bash scripts/sign-dmg.sh "packages/app/release/StreamMagpie-$V-arm64.dmg"
```

The script does three things in one order: `codesign` → `notarytool submit
--wait` → `stapler staple`.

⚠ **THE ORDER IS LOAD-BEARING. Signing invalidates an existing ticket**, so a
sequence that signs after stapling produces a file that passes every local check
and **fails on a clean Mac**. Sign first, notarize what was signed, staple last.
Do not reorder the script, and do not re-`codesign` the DMG afterwards for any
reason.

⚠ If notarization returns `HTTP 403 - A required agreement is missing or has
expired` while the certificate is still valid: certificate validity says nothing
about **account** validity, and agreements are per-team. Accept it in the
developer portal with the team switcher set to Intheday Ltd.

## Step 5 — Verify

This set deliberately mirrors `ship-gumroad`'s preflight a–g, so that ship's
gates pass first try rather than sending the release back here a day later.

```bash
DMG="packages/app/release/StreamMagpie-$V-arm64.dmg"
ls -lh "$DMG"

# a/b — the DMG is signed
codesign -dvv "$DMG" 2>&1 | grep -E "Authority|TeamIdentifier"
# want: Authority=Developer ID Application: Intheday Ltd (29UYFH4USR)
#       TeamIdentifier=29UYFH4USR

# c — notarized, and stapled
spctl -a -t open --context context:primary-signature -v "$DMG" 2>&1   # want: accepted
xcrun stapler validate "$DMG"                                          # want: validated

# d — mount, and check the version the bundle actually carries
MP=$(mktemp -d)
hdiutil attach "$DMG" -nobrowse -quiet -mountpoint "$MP"
defaults read "$MP/StreamMagpie.app/Contents/Info.plist" CFBundleShortVersionString  # want: $V

# e — the payloads, read from the MOUNTED app and never from vendor/
RES="$MP/StreamMagpie.app/Contents/Resources"
"$RES/ffmpeg/ffmpeg" -version | head -1
"$RES/ffmpeg/ffmpeg" -version | grep -- "--enable-libmp3lame"          # want a match
otool -L "$RES/ffmpeg/ffmpeg"  | tail -n +2 | grep -v -E "/usr/lib|/System/Library|@rpath"
otool -L "$RES/ffmpeg/ffprobe" | tail -n +2 | grep -v -E "/usr/lib|/System/Library|@rpath"
ls "$RES/ffmpeg/COPYING.LGPLv2.1" "$RES/ffmpeg/LICENSE.md"
"$RES/python/bin/python3" --version
test -x "$RES/js/qjs" && ls -l "$RES/js/qjs"
ls "$RES/ytdlp"/yt_dlp*.whl
codesign -dvv "$RES/ffmpeg/ffmpeg"      2>&1 | grep -E "Authority|TeamIdentifier"
codesign -dvv "$RES/python/bin/python3" 2>&1 | grep -E "Authority|TeamIdentifier"

# the nested tree mac.binaries does NOT name — signed by the recursive pass
find "$RES/python" -type f \( -name '*.so' -o -name '*.dylib' \) \
  -exec codesign -dvv {} \; 2>&1 | grep -c "TeamIdentifier=29UYFH4USR"   # want 10

# f — the icon, read from the MOUNTED app
shasum -a 256 "$MP/StreamMagpie.app/Contents/Resources/icon.icns"

hdiutil detach "$MP" -quiet
```

⚠ `-dvv` needs **two** v's. At `-dv` the Authority lines are not printed at all,
which reads exactly like an unsigned binary when it is merely under-verbose.

⚠ **Every Mach-O in the bundle should come back signed, not just the four
`mac.binaries` names — and this skill used to say the opposite.**
electron-builder 26.15.3 signs the named list with the entitlements
(`signing additional user-defined binaries`) and then makes a **separate
recursive pass** over the finished `.app`
(`signing file=release/mac-arm64/StreamMagpie.app`). On 2026-08-23 all **14**
Mach-O images carried `Authority=Developer ID Application: Intheday Ltd
(29UYFH4USR)`, `TeamIdentifier=29UYFH4USR` and `flags=0x10000(runtime)`,
including the ten under `Contents/Resources/python/lib/` (libpython3.12, six
Tcl/Tk dylibs, three `lib-dynload/*.so`). `[verified: run 2026-08-23]` A nested
image that comes back **unsigned** is therefore a regression to investigate, not
the expected state.

⚠ `spctl` and `stapler validate` both fall back to an **online** ticket lookup,
so a pass proves *notarized*, not necessarily *stapled*. Only a machine with
networking off settles that. Say it that way in the report.

⚠ `otool -L` wants **zero** lines out of each grep. A `/opt/homebrew` line is a
binary that runs on this machine and fails on every customer's.

**Icon digests, three outcomes:**

- **equals `6ee152c8a54a0859e6d84d3ecd20d0a71564272b59c0656ccc9607550686b7b0`** —
  hard FAIL. That is the retired placeholder; the build predates the icon commit.
  Stop.
- **equals `4862602c66d1d0eaddd3c55ad4f96de4551e62d6a6c0930aa0e60afa7d2ca553`** —
  expected. Necessary, never sufficient: a digest proves which bytes shipped, not
  that the art is right.
- **neither** — WARN. Either the build did not pick up
  `packages/app/build/icon.icns`, or the art changed and these Constants were
  never updated. Compare against `shasum -a 256 packages/app/build/icon.icns` and
  say **which** it is; do not guess past it.

⚠ **Always `hdiutil detach`, including on failure.** A verification that stops
early still leaves the image mounted.

## Step 6 — Hand off

Report the artifact path, its size, the three grep counts, and every row of the
verification set with its actual output. Then say, in these terms:

> The DMG is built and verified. **Shipping is
> `.claude/skills/ship-gumroad`** — it re-runs these gates and blocks on the
> human gate (install into /Applications, launch, paste a URL, save an m4a
> **and** an MP3, play both).

**This skill never uploads, never tags, and never pushes.** If asked to, say that
`ship-gumroad` owns it — and that today it will refuse anyway, because
`YOUR_GUMROAD_PRODUCT_ID` and `YOUR_GUMROAD_PRODUCT_URL` are still literal
placeholders.

## Failure modes worth naming

| Symptom | Cause |
|---|---|
| `notarytool` cannot find the profile | the `streammagpie` keychain profile was never stored — run `store-credentials` first (`docs/DISTRIBUTION.md` → "Before the first ship, once"). ⚠ The Apple ID that works is **not** the git-committer address |
| `Please remove prefix "Developer ID Application:"` | the prefixed identity was passed as `CSC_NAME`. `CSC_NAME` takes the bare qualifier; raw `codesign` takes the prefixed form — the inversion in Constants |
| `skipped macOS notarization` in the log | credentials were not found; **the build is a dud** even though it exited 0. Do not sign it, do not ship it, fix the profile and rebuild |
| `file source doesn't exist` in the log | a `vendor/` directory was empty at build time; the **DMG shipped hollow**. Run the matching vendor script and rebuild — a hollow DMG cannot be repaired by signing it |
| no DMG in `release/` at all | `npm run dist` was run instead of `npm run dist:dmg`; `--dir` produces the unpacked `.app` only |
| `codesign -dvv "$DMG"` says not signed | `scripts/sign-dmg.sh` was not run, or was run before the DMG existed |
| `spctl` rejects a stapled DMG | it was re-signed after stapling — signing invalidates the ticket. Rebuild the pass in order: sign, notarize, staple |
| MP3 conversion fails while m4a works | the vendored ffmpeg has no `libmp3lame`; the step 1 grep is where this is meant to be caught |
| a payload has no `Authority` line | a **regression**, not the norm — and the opposite of what this table used to say. electron-builder 26.15.3 signs the `mac.binaries` list with the entitlements and then makes a separate recursive pass over the whole `.app`; on 2026-08-23 all 14 Mach-Os came back on team `29UYFH4USR`. An unsigned one means that pass did not reach it: check the file was inside the `.app` at signing time, and that step 3's greps were clean |
| notarization **Invalid**, log names `python/**/lib-dynload/*.so` | **did not happen on 2026-08-23** — electron-builder's recursive pass had already signed the whole nested tree, so the submission contained nothing unsigned to reject (`docs/DISTRIBUTION.md` → "The two risk hypotheses"). If it happens anyway, that pass did not run or did not reach those files: look for `signing file=release/mac-arm64/StreamMagpie.app` in the log. A manual deep-sign over `Contents/Resources/python`, innermost first, is the fallback — **not** an entitlement |
| the packaged app dies by **instant SIGKILL** when Python starts, nothing in any log | hardened-runtime library validation against CPython's `dlopen`ed C extensions. **Did not happen on 2026-08-23**: from the installed hardened-runtime app, the bundled interpreter imported ssl, zlib, ctypes, sqlite3, hashlib, bz2, lzma, socket and binascii, exit 0, and loaded yt_dlp off the floor wheel. But a payload change can reintroduce it and **an empty log is still the signature.** Establish what got rejected before adding `com.apple.security.cs.disable-library-validation` to `packages/app/build/entitlements.mac.plist` — a same-team signature is the narrower fix and makes the entitlement unnecessary |
| the app runs from `/private/var/folders/.../AppTranslocation/<uuid>/d/StreamMagpie.app` instead of `/Applications`, and `process.resourcesPath` points somewhere nobody installed to | **not a fault.** While the quarantine attribute is present macOS translocates the bundle, executing it from a randomized read-only copy. Observed on 2026-08-23; the app launched and ran fine there. `xattr -cr` on the installed bundle clears the attribute and it then runs from `/Applications` proper, signature intact (`codesign --verify --strict` still passes). Do not chase this as a path bug, and do not clear quarantine to make a Gatekeeper check pass — that check *is* the quarantine |
| `AMFIUnserializeXML: syntax error near line N` at signing | a literal double hyphen inside an XML comment in `packages/app/build/entitlements.mac.plist`. `plutil -lint` cannot catch it; the line number is accurate |
