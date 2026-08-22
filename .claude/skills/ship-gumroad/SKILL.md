---
name: ship-gumroad
description: Publish a built StreamMagpie DMG to Gumroad as the product's new download. Use when the user says "ship to Gumroad", "publish the release", "upload the DMG", "push 0.1.x to customers", or after a version bump when the release build is ready. Verifies signing, notarization, stapling, the bundled extractor/ffmpeg/python/js payloads, the real app icon and version consistency, blocks on the human gate, then replaces the product file in place.
---

# ship-gumroad

Upload leg of a StreamMagpie release: takes an **already built, signed, notarized
and stapled** DMG and makes it the product's download on Gumroad.

**Out of scope** — all of it belongs to
[`.claude/skills/build-dmg`](../build-dmg/SKILL.md): the vendor scripts
(`build-ffmpeg.sh`, `vendor-python.sh`, `vendor-js.sh`, `vendor-ytdlp.sh`),
`npm run dist:dmg`, and the `scripts/sign-dmg.sh` sign → notarize → staple pass.
**This skill verifies that work; it does not perform it.** If a gate below fails,
the answer is to go back to `build-dmg`, not to fix it from here.

## Constants

| | |
|---|---|
| Gumroad product ID | `YOUR_GUMROAD_PRODUCT_ID` |
| Product URL | `YOUR_GUMROAD_PRODUCT_URL` |
| Artifact | `packages/app/release/StreamMagpie-$V-arm64.dmg` |
| Version source | `packages/app/package.json` (single source of truth) |
| Retired placeholder icon digest | `6ee152c8a54a0859e6d84d3ecd20d0a71564272b59c0656ccc9607550686b7b0` |
| Current icon digest (build/icon.icns) | `4862602c66d1d0eaddd3c55ad4f96de4551e62d6a6c0930aa0e60afa7d2ca553` |

⚠ **HARD RULE — REFUSE TO UPLOAD WHILE THE PLACEHOLDERS ARE PLACEHOLDERS.** The
product does not exist on Gumroad yet. If `YOUR_GUMROAD_PRODUCT_ID` or
`YOUR_GUMROAD_PRODUCT_URL` still reads literally as written above, **stop
immediately**: do not call `gumroad products update`, do not guess a product ID
from `gumroad products list`, do not create the product. Report that the product
has to be created first and these two constants filled in by a human (and the
same pair recorded in `docs/DISTRIBUTION.md`). **An upload to the wrong product
ID replaces some other product's download** — it is not a failed command, it is a
different product's customers getting this DMG.

Two quoting traps, both of which fail in confusing ways:

- Gumroad product IDs are base64 and usually **end in `==`**. Always
  single-quote — `PID='…=='` — never leave it bare.
- The DMG filename has no space in it today. Quote `"$DMG"` anyway; the version
  substitution is the part that rots.

## Rules

- Every mutating `gumroad` call runs with `--dry-run` first. Show the user the
  output, then run it for real. **No exceptions.**
- Never attach the DMG to a GitHub Release or any public CDN
  (`docs/DISTRIBUTION.md` hard rules 1–2). This skill's only upload target is
  Gumroad. The extractor carve-out in those rules covers `yt_dlp-*.whl`,
  `extractor-manifest.json` and its `.sig` — **not** anything this skill touches.
- Never print, echo, or write the Gumroad token. `gumroad auth status` is the
  only credential check needed.
- If any gate fails, **stop and report**. Do not offer to skip a gate. Do not
  upload "anyway". The user can re-run once the gate genuinely passes.
- **Every rebuild re-earns its gates.** Nothing about this project's signing,
  notarization or payload bundling has ever been observed even once
  (`docs/DISTRIBUTION.md` → "What has not been proven"), so there is not even a
  precedent to over-trust. Run every row, every time.

## Step 1 — Preflight

Run these and show a compact pass/fail table. **Every row must pass.**

```bash
cd "$(git rev-parse --show-toplevel)"
V=$(node -p "require('./packages/app/package.json').version")
DMG="packages/app/release/StreamMagpie-$V-arm64.dmg"
echo "version=$V"; ls -lh "$DMG"
```

**a. Artifact exists** — `ls "$DMG"`. If missing, the build was never run for
this version, or the version was bumped after the build. Stop; go to `build-dmg`.

**b. DMG is signed.** electron-builder signs the `.app` but *not* the DMG around
it (`docs/DISTRIBUTION.md` step 3) — an unsigned DMG here means
`scripts/sign-dmg.sh` was never run.

```bash
codesign -dvv "$DMG" 2>&1 | grep -E "Authority|TeamIdentifier"
# want: Authority=Developer ID Application: Intheday Ltd (29UYFH4USR)
#       TeamIdentifier=29UYFH4USR
```

⚠ `-dvv` needs **two** v's. At `-dv` the Authority lines are not printed at all,
which reads exactly like an unsigned DMG when it is merely under-verbose.

**c. DMG is notarized.**

```bash
spctl -a -t open --context context:primary-signature -v "$DMG" 2>&1
# want: accepted / source=Notarized Developer ID
```

> `spctl` and `stapler validate` both fall back to an **online** ticket lookup,
> so a pass here proves *notarized*, never *stapled*. Report it that way. Only a
> machine with networking off settles stapling.

**d. Version consistency inside the bundle** — catches a stale rebuild where
`package.json` moved but the artifact did not. **The mount stays up for gates e
and f.**

```bash
MP=$(mktemp -d)
hdiutil attach "$DMG" -nobrowse -quiet -mountpoint "$MP"
defaults read "$MP/StreamMagpie.app/Contents/Info.plist" CFBundleShortVersionString
# want: exactly $V
```

**e. PAYLOAD gate — read from the MOUNTED app, never from `vendor/`.** This is
the sharpest trap in the project. Every other check passes even if bundling
silently failed: `extraResources` fails open (`file source doesn't exist` at
WARN, build still exits 0), and the development machine has working copies in
`vendor/` **and** on `PATH` to mask it. Four independent payloads, four ways to
ship a hollow DMG.

```bash
RES="$MP/StreamMagpie.app/Contents/Resources"

# ffmpeg: exists, runs, and can encode MP3
"$RES/ffmpeg/ffmpeg" -version | head -1
"$RES/ffmpeg/ffmpeg" -version | grep -- "--enable-libmp3lame"
# want: one match. MP3 output is a SOLD FEATURE. An ffmpeg without libmp3lame
# gives an app where m4a works and MP3 fails at save time, on the customer's
# machine, after the download.

# ffmpeg + ffprobe are self-contained
otool -L "$RES/ffmpeg/ffmpeg"  | tail -n +2 | grep -v -E "/usr/lib|/System/Library|@rpath"
otool -L "$RES/ffmpeg/ffprobe" | tail -n +2 | grep -v -E "/usr/lib|/System/Library|@rpath"
# want: ZERO lines from each. A /opt/homebrew line is a binary that runs here
# and fails on every customer's Mac.

# LGPL compliance files travel with the binaries
ls "$RES/ffmpeg/COPYING.LGPLv2.1" "$RES/ffmpeg/LICENSE.md"
# want: both present. Their absence is a licence violation, not a cosmetic miss.

# CPython
"$RES/python/bin/python3" --version
# want: a version line, and it proves the binary actually executes.

# JS runtime — the one electron-builder.yml's mac.binaries names
ls -l "$RES/js/qjs" && test -x "$RES/js/qjs"
# want: present and executable. If the yml's mac.binaries has moved to a
# different runtime, check THAT path — the signed one is the one that matters.

# the extractor wheel
ls "$RES/ytdlp"/yt_dlp*.whl
# want: at least one wheel. No wheel means no extractor and the app cannot
# resolve a single URL.

# the two signed loose Mach-Os
codesign -dvv "$RES/ffmpeg/ffmpeg"      2>&1 | grep -E "Authority|TeamIdentifier"
codesign -dvv "$RES/python/bin/python3" 2>&1 | grep -E "Authority|TeamIdentifier"
# want: Authority=Developer ID Application: Intheday Ltd (29UYFH4USR)
```

⚠ **THE SIGNING ROWS ARE THE ONES MOST LIKELY TO BE WRONG.** A loose Mach-O in
`Resources` is **not** walked and re-signed the way a nested `.app` bundle is —
only the `mac.binaries` list in `electron-builder.yml` makes it happen, and that
list names exactly four files. An ad-hoc or absent signature here means the build
signed the app and not its payloads.

⚠ **And the python `.so` tree is a KNOWN OPEN RISK, not a passing row.** The
CPython payload carries many Mach-O C extensions under `lib-dynload/` plus
`libpython3.12.dylib`, and `mac.binaries` names none of them. That is hypothesis
(a) in `docs/DISTRIBUTION.md` → "What has not been proven". If notarization was
rejected, read that section before guessing; if it passed, say so plainly — that
is new information this project has never had.

**f. ICON gate — read the icon out of the MOUNTED DMG's app bundle**, not out of
the source tree. A build that failed to pick up the committed
`packages/app/build/icon.icns` is exactly what this gate exists to catch, and the
source file is green in precisely that case.

```bash
ICNS="$MP/StreamMagpie.app/Contents/Resources/icon.icns"
shasum -a 256 "$ICNS"

hdiutil detach "$MP" -quiet
```

Three outcomes, and only the first is a stop:

- **FAIL — it equals the retired placeholder digest**
  (`6ee152c8a54a0859e6d84d3ecd20d0a71564272b59c0656ccc9607550686b7b0`, Constants
  table). The build carries the retired stand-in. **Stop; do not upload.** The
  icon is the first thing a buyer sees, in the DMG window.
- **WARN — it differs from the current icon digest**
  (`4862602c66d1d0eaddd3c55ad4f96de4551e62d6a6c0930aa0e60afa7d2ca553`). Either
  the build did not pick up the committed `build/icon.icns`, or the art changed
  and the Constants table was never updated. **Both are real and they are not the
  same problem: say which one it is** (compare against
  `shasum -a 256 packages/app/build/icon.icns` in the source tree) before going
  on. Do not upload on a guess.
- **Match — necessary, never sufficient.** A digest proves which *bytes* shipped
  and can prove nothing about whether the art is right.

**So the human visual confirm is mandatory, on every run, whatever the digest
says.** Ask the user to look at the `.app` in the DMG window in Finder and
confirm the StreamMagpie icon is the real art. "The hash matched" is not a pass
on its own.

⚠ **Always `hdiutil detach "$MP"`, including on failure.** A gate that stops
early still leaves a mounted image behind, and the next run's `mktemp -d` mount
will not tell you about it.

**g. Build-log fail-open check** — *advisory only*, `/tmp/streammagpie-build.log`
is ephemeral. If it exists and covers this version, the three greps must be at
their target values:

```bash
grep -c "skipped macOS notarization" /tmp/streammagpie-build.log   # want 0
grep -c "file source doesn't exist"  /tmp/streammagpie-build.log   # want 0
grep -c "notarization successful"    /tmp/streammagpie-build.log   # want 1
```

If the log is absent or stale, **say so plainly — do not report it as a pass.**
An absent log is missing evidence, which is a different thing from evidence of
success.

**h. Gumroad state.** The rich-content `fileEmbed` node carries only an opaque
`attrs.id`, **not** a filename — so read `.product.files[]`, which is the
authoritative list, rather than the content document.

```bash
gumroad auth status
PID='YOUR_GUMROAD_PRODUCT_ID'
gumroad products view "$PID" --json | jq '.product.files[] | {id, name, size, filetype}'
```

Two things must hold:

- **Exactly one file.** `products update --file` replaces embeds *in place*, one
  `--file` per existing embed. If the product has more than one, in-place
  replacement will not do what this skill assumes — stop and re-plan against the
  actual document rather than guessing.
- **It is not already this version.** If `.name` already contains `$V`, this
  release is shipped. Stop; report it as already done, and compare `size` against
  the local DMG (`stat -f%z "$DMG"`) to confirm it is byte-identical rather than
  a same-named rebuild.

## Step 2 — Human gate (blocking)

`docs/DISTRIBUTION.md`: **nothing about this app's packaged behaviour has ever
been observed.** No log answers whether a customer can paste a URL and get a file
that plays. Ask the user, and wait.

Ask specifically — name the build, ask what was **on screen**:

> Has a human installed **$V** — this exact build, from this DMG, into
> /Applications — launched it, pasted a URL, and saved both an m4a and an MP3
> that then played? What did the sleeve show, and what happened on first launch:
> did it open, or did Gatekeeper refuse it?

Three things have to be true and all three need eyes:

1. **It launched from `/Applications` on first launch** — Gatekeeper accepted it
   with a normal double-click, with **no right-click-open workaround**. The
   workaround is how an un-notarized or un-stapled build looks fine to the person
   testing it and refuses on the customer's Mac.
2. **A real YouTube URL was pasted and the sleeve preview rendered** — the title
   and the thumbnail both appeared. That is the extractor, the bundled Python,
   the wheel and the JS runtime all working end to end; nothing short of it
   exercises that chain.
3. **Both an m4a and an MP3 were saved from that URL, and BOTH files play** in
   Music or QuickTime. The MP3 is the half that proves `libmp3lame` is really in
   the bundled ffmpeg, and it is the half most likely to be skipped.

Do not accept "the logs looked fine", "it's the same pipeline", or "it was only a
copy change" as a pass. **Those are reasons to *expect* a pass, not evidence of
one.** If the answer is no, stop and point at `docs/DISTRIBUTION.md`'s ship
checklist.

## Step 3 — Upload

`products update --file` replaces the existing rich content file embed **in
place**, so this is the whole operation — buyers keep one download, always the
latest.

```bash
gumroad products update "$PID" --file "$DMG" --dry-run
```

Show the dry-run. Then run the **identical** command without `--dry-run`.

Do **not** pass `--file-name`. The display name defaults to the basename
(`StreamMagpie-0.1.0-arm64`), which keeps the version legible in the buyer's
library and consistent across releases. A custom name would break that convention
and defeat gate (h), which matches `$V` against `.name`.

**If the upload fails ambiguously** with `complete_state_unknown`, the bytes are
already uploaded — finalize the saved recovery manifest rather than re-sending:

```bash
gumroad products update "$PID" --file "$DMG" --json > /tmp/sm-upload.json   # capture on failure
jq '.error.recovery' /tmp/sm-upload.json > /tmp/sm-recovery.json
gumroad files complete --recovery /tmp/sm-recovery.json --yes --json
# or, to reclaim an orphaned multipart upload:
gumroad files abort --upload-id <id> --key <key> --yes
```

⚠ **An upload that hangs near the end is expected at this size** — the DMG
carries a Python runtime, a static ffmpeg and a JS engine. **Do not kill it
blindly**: a killed upload orphans a multipart session, which is what
`files abort` is for.

## Step 4 — Verify, byte-exact

```bash
gumroad products view "$PID" --json | jq '.product.files[] | {name, size, filetype}'
stat -f%z "$DMG"
```

Confirm all four: exactly **one** file; `.name` carries `$V`; `.filetype` is
`dmg`; and `.size` equals the local DMG byte count **exactly**. A size mismatch
means the upload truncated — re-run rather than assuming success. Report the
product URL so the user can eyeball it.

## Step 5 — After the upload

1. **Tag the source** — source only, **zero release assets**
   (`docs/DISTRIBUTION.md` hard rule 3). Push only when the user asks:
   ```bash
   git tag "v$V"
   # git push origin "v$V"   # only on request
   ```
   ⚠ The extractor carve-out does not apply to this tag. A product tag carries
   no files at all.
2. **Release note.** Keep it honest about what is still open. Do not write a
   claim the gates above did not earn.
3. **Update the docs** — record the human-gate result in `docs/DISTRIBUTION.md`
   so the next release inherits an accurate starting point. **Characteristics
   only** (hard rule 6): duration band, container, output formats saved, rough
   file size, elapsed time, whether the extractor needed the JS runtime. **Never
   a real video title, channel name, or watch URL.** If an example URL is
   genuinely needed, the canonical public test video id `jNQXAC9IVRw` is the only
   one permitted.
4. Optionally offer to email customers that a new version is available. Buyers
   re-download from their library; there is no in-app updater for the app itself.

## Failure modes worth naming

| Symptom | Cause |
|---|---|
| Constants still read `YOUR_GUMROAD_PRODUCT_ID` / `YOUR_GUMROAD_PRODUCT_URL` | the product does not exist yet — refuse to upload, do not guess an ID, do not create it |
| `codesign -dvv` says "not signed at all" | the `scripts/sign-dmg.sh` pass was skipped — sign → notarize → staple, **in that order** (signing invalidates an existing ticket) |
| `codesign` prints no `Authority` lines | you used `-dv`; it needs `-dvv` |
| `spctl` rejects | DMG notarized but not signed first, or notarization silently skipped (grep g) |
| Info.plist version ≠ `$V` | artifact is stale; rebuild via `build-dmg` |
| `otool -L` shows `/opt/homebrew` | the vendored ffmpeg is a Homebrew copy; `extraResources` bundled it happily and it fails on every Mac but this one |
| a `Contents/Resources` payload is missing entirely | `extraResources` failed open (`file source doesn't exist` at WARN) — a vendor directory was empty at build time and the DMG shipped hollow |
| **MP3 save fails while m4a works** | the bundled ffmpeg was built without `--enable-libmp3lame` — the wrong binary was vendored. m4a masks it completely; only the MP3 half of the human gate catches it |
| payload signed ad-hoc, or no `Authority` line | `mac.binaries` did not name it; a loose Mach-O is not walked and re-signed like a nested bundle |
| **the app dies by instant SIGKILL when Python starts**, nothing in any log | hardened-runtime library validation against CPython's `dlopen`ed C extensions, or an unsigned `.so` tree — the two documented hypotheses in `docs/DISTRIBUTION.md` → "What has not been proven". **An empty log is the signature.** Establish what got rejected before widening entitlements |
| notarization Invalid, log names `lib-dynload/*.so` paths | hypothesis (a): the python tree's nested Mach-Os were never signed. The fix is a deep-sign pass, not an entitlement |
| shipped icon digest matches the **retired** placeholder | a stale build predating the icon commit — refuse; that icon is a buyer's first impression, in the DMG window |
| shipped icon digest matches neither constant | the build did not pick up the committed `build/icon.icns`, or the art moved without the Constants table — a WARN to resolve, not to guess past |
| upload hangs near the end | expected on a DMG this size; do not kill it blindly — a killed upload orphans a multipart session (`files abort`) |
| `extractor-manifest` 404 in the app's log | **NORMAL** until the first wheel release exists. It is not a ship blocker and it is not one of the three build-log greps |
| the DMG landed on the wrong product | the horror row. `products update` **replaces** that product's file in place, so some other product's customers now download StreamMagpie. This is why a placeholder ID is a hard stop rather than a prompt |
