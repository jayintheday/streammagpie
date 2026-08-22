# Licensing — the LGPL boundary

> **Status:** written 2026-08-22, before the first packaged build exists. Every
> claim about what is *inside* the DMG is therefore `[inferred]` and marked as
> such; the claims about what the scripts and configuration say are
> `[verified: source]`.
>
> This is engineering guidance, not legal advice.

StreamMagpie is the heaviest third-party bundle in the suite. The app is a few
thousand lines of TypeScript wrapped around four upstream projects, and three of
those four ship as binaries inside the DMG. That is the whole of the licensing
problem, and it is tractable because **none of it is linked**: every upstream
component is a separate executable that the app spawns.

## The bundle

| Component | Lands at | Licence | How it is used |
|---|---|---|---|
| ffmpeg / ffprobe (static, arm64) | `Contents/Resources/ffmpeg` | **LGPL-2.1-or-later**, with libmp3lame (LGPL) | subprocess, spawned by yt-dlp for remux and MP3 encode |
| CPython | `Contents/Resources/python` | **PSF License Agreement** | subprocess interpreter |
| yt-dlp wheel | `Contents/Resources/ytdlp`, and Application Support after an update | **Unlicense** (public domain dedication) | imported by the bundled CPython, run as `python -m yt_dlp` |
| QuickJS (`qjs`), or Deno | `Contents/Resources/js` | **MIT** | subprocess, invoked by yt-dlp for signature solving |
| StreamMagpie itself | the app | **MIT** | — |

`[verified: source — packages/app/electron-builder.yml extraResources, and the
four scripts under scripts/ that populate vendor/]`

---

## 1. ffmpeg — the only licence that constrains anything

ffmpeg's default configuration is **LGPL-2.1-or-later**, and it stays there as
long as no GPL-only component is enabled. MP3 encoding does **not** cost us
that: libmp3lame is itself LGPL, so `--enable-libmp3lame` is available in a
non-GPL build. `[inferred — confirm against the LICENSE.md of the build actually
vendored; ffmpeg's own LICENSE.md is the authority on which parts of the tree a
given configuration pulled in]`

### The rule

**Build with `--enable-libmp3lame`. Never with `--enable-gpl`, never with
`--enable-nonfree`, and not with `--enable-version3` unless somebody decides to
move to LGPLv3 on purpose.** No x264, no x265, no libfdk-aac. StreamMagpie
converts audio; it has no use for any of them.

`scripts/build-ffmpeg.sh` states this at the top of the file and repeats it in
its `--help`. `[verified: source]`

### ⚠ The Homebrew trap, which is a licence bug and not a portability bug

`build-ffmpeg.sh` also says *do not copy Homebrew ffmpeg into the bundle*. The
reason is worth spelling out, because the script's automated check does not
catch it: the script greps `otool -L` output for `/opt/homebrew`, which catches
a **dynamically linked** Homebrew binary and would happily pass a **statically
linked** one built from the same GPL configuration.

Homebrew's ffmpeg is GPL. On this machine:

```
ffmpeg version 8.1.1
configuration: … --enable-version3 --enable-gpl --enable-libsvtav1 --enable-libopus
               --enable-libx264 --enable-libmp3lame --enable-libdav1d --enable-libvmaf
               --enable-libvpx --enable-libx265 …
```

**[verified: run 2026-08-22]** — `ffmpeg -version` on the development machine.

Shipping that binary inside StreamMagpie would make the DMG a GPL distribution
without anyone deciding to, and the app's MIT licence would become a false
statement about what the customer received. **Judge a candidate ffmpeg by its
`configuration:` line, not by whether it runs.**

### How the LGPL obligations are met

1. **We do not modify ffmpeg.** We configure it. If that ever changes — even a
   one-line patch — the patch is itself LGPL and has to ship as a readable diff
   alongside the source. Prefer configuration and build flags precisely so this
   stays simple.
2. **The licence texts ship in the DMG, beside the binaries.**
   `COPYING.LGPLv2.1` and ffmpeg's `LICENSE.md` go into
   `vendor/ffmpeg/arm64/`, which electron-builder copies unfiltered to
   `Contents/Resources/ffmpeg`. **[verified: source]** — the extraResources
   mapping, and [`DISTRIBUTION.md`](DISTRIBUTION.md) already records the
   requirement.
   ⚠ `vendor/ffmpeg/arm64/` currently contains nothing but `.gitkeep`, so this
   obligation is **unmet in the working tree** and is met only at vendor time.
   It is the first item on the checklist below for that reason.
   `[verified: run 2026-08-22]`
3. **Source availability is by pinned version.** The exact ffmpeg version, the
   tarball URL it came from, and the full configure line are recorded in a
   `README` inside `vendor/ffmpeg/arm64/`. A recipient who wants the
   corresponding source gets an unambiguous pointer to the identical upstream
   tarball plus the configuration that produced the binary. ⚠ That README does
   not exist yet either. `[verified: run 2026-08-22]`
4. **The relinking requirement is satisfied structurally, because there is no
   linking.** LGPL-2.1 §6 exists so that a user can replace the library with
   their own version. StreamMagpie does not link `libavcodec` or anything else
   into its process — `ffmpeg` and `ffprobe` are **separate executables invoked
   as subprocesses**, which is the loosest possible coupling and the one the
   licence is least concerned about. A user who wants a different ffmpeg builds
   one and points the app at it; the resolution order reads
   `STREAMMAGPIE_FFMPEG` from the environment before it looks in the bundle.
   `[verified: source — packages/app/src/main/helper-paths.ts sets that variable
   only if it is unset, so an externally supplied value wins]`

   ⚠ Honest caveat: swapping the binary **inside** a signed, hardened-runtime
   `.app` breaks its code signature, so in-place replacement is not the route.
   Setting the environment variable, or building from the MIT source, is. This
   is why the subprocess argument matters rather than being a technicality —
   the substitution freedom is real, it just does not run through the signed
   bundle.

---

## 2. CPython — permissive, with one thing to check

The interpreter comes from `python-build-standalone` (a redistributable CPython
build), pinned in `scripts/vendor-python.sh` to a `cpython-3.12.11+<tag>`
`aarch64-apple-darwin` `install_only` archive. `[verified: source]`

CPython is under the **PSF License Agreement** — permissive, GPL-compatible, and
satisfied by shipping the licence text and stating that the work is a
redistribution. The `install_only` archives carry their licence material with
them; it must survive into `Contents/Resources/python`. `[inferred]`

⚠ **The thing to actually check is not CPython, it is what CPython was built
against.** A standalone Python build links a set of third-party libraries —
OpenSSL, SQLite, libffi, a line-editing library, compression libraries — and
those carry their own licences. The one that matters is the line editor: **GNU
readline is GPL-3.0**, and a CPython linked against it would drag the whole
bundle into GPL territory the same way a GPL ffmpeg would. Builds intended for
redistribution normally use BSD-licensed libedit for exactly this reason, but
that is an assumption until it is read. `[inferred]`

`python-build-standalone` distributions ship machine-readable licence metadata
(a `PYTHON.json` plus a licences directory) enumerating every bundled
dependency. **Read it at vendor time and record the result.** That is a
five-minute check that answers this permanently for a given pin, and it is on
the checklist.

---

## 3. yt-dlp — public domain, nothing to satisfy

yt-dlp is released under the **Unlicense**, a public-domain dedication.
Redistribution of the wheel — inside the DMG, and as a GitHub Release asset for
the extractor updater — is unrestricted.

**[verified: run 2026-08-22]** — read out of the locally vendored wheel
(untracked, produced by `scripts/vendor-ytdlp.sh`): its `dist-info/METADATA`
declares `License-Expression: Unlicense`, and the wheel carries its own
`dist-info/licenses/LICENSE`.

Two consequences worth noting:

- **The licence text travels automatically.** It is inside the `.whl`, so no
  separate copying step can forget it — for the floor wheel in the DMG *and* for
  every wheel the updater downloads later.
- **The updater's carve-out is a distribution-policy question, not a licensing
  one.** Publishing `yt_dlp-*.whl` on this repo's GitHub Releases is permitted by
  the Unlicense outright; the reason it is written down in
  [`DISTRIBUTION.md`](DISTRIBUTION.md) is to keep it from being read as
  permission to publish anything *else* there.

---

## 4. The JS runtime — MIT, but know which one you shipped

yt-dlp needs a JavaScript runtime to solve YouTube's signature challenges.
StreamMagpie bundles **QuickJS** (`qjs`) by preference, with **Deno** as the
fallback. Both are **MIT**. `[inferred — confirm against the binary actually
vendored]`

⚠ `scripts/vendor-js.sh` copies whichever of `qjs` or `deno` it finds on `PATH`,
and copies **the binary alone**. `[verified: source]` So the bundle can end up
carrying a runtime with no licence text beside it, and — worse for a compliance
record — nobody afterwards can tell from the tree *which* runtime, at which
version, from which source. Two things follow, both on the checklist: place the
runtime's `LICENSE` next to the binary in `vendor/js/`, and record its origin
and version in a `README` there.

---

## 5. StreamMagpie itself — MIT, and why it can stay MIT

The app's own source is **MIT** (root [`LICENSE`](../LICENSE), and the
`license` field of every `package.json`). `[verified: source]`

That holds because every upstream component is either permissive (CPython,
yt-dlp, the JS runtime) or LGPL used across a process boundary (ffmpeg). Nothing
copyleft is linked into the app, and nothing GPL is present at all. The MIT
statement on the repo is therefore a description of the whole shipped artifact,
not just of the files we wrote — and that is the property worth protecting.

**Selling the DMG is unaffected.** None of these licences restricts charging for
a build; what they restrict is misrepresenting what is inside it and withholding
what has to travel with it. [`EULA.md`](EULA.md) covers the terms of sale, and it
is explicit that the source is MIT and free.

---

## YouTube's terms are not a licensing matter

Nothing above restricts what the software may be used *for*. Every upstream
licence here is about copying and modifying the code.

YouTube's terms of service are a **contract between the user and YouTube**, and
downloading may violate them. That is a **user obligation**, documented where a
user will actually meet it — [`EULA.md`](EULA.md) and the README — and not
something a licence file can resolve. Do not restate it as a licensing
constraint in this document or in code comments; doing so muddles two unrelated
things and makes the real licensing position harder to audit.

The related product decision, recorded in [`AGENTS.md`](../AGENTS.md): **no Mac
App Store**, per App Review guideline 5.2.3. That is Apple policy, not copyright
law, and it is a scope decision rather than a licensing one — but it is the
reason direct distribution is the only channel, which is in turn why the LGPL
compliance route above (files beside the binaries in a DMG) is available at all.

---

## Release compliance checklist

Every release. Gate the upload on it. Where the DMG may go:
[`DISTRIBUTION.md`](DISTRIBUTION.md).

**Licence texts present in the DMG payload:**

- [ ] `Contents/Resources/ffmpeg/COPYING.LGPLv2.1`
- [ ] `Contents/Resources/ffmpeg/LICENSE.md` (ffmpeg's own)
- [ ] `Contents/Resources/ffmpeg/README.StreamMagpie.txt` recording version,
      tarball URL and the full configure line (the vendor script writes it)
- [ ] `Contents/Resources/python/LICENSE.python.txt` and
      `Contents/Resources/python/README.StreamMagpie.txt`
- [ ] `Contents/Resources/js/LICENSE.quickjs.txt` beside `qjs`, plus
      `Contents/Resources/js/README.StreamMagpie.txt` naming version and origin
- [ ] the yt-dlp wheel is intact (its licence is inside it — verify the wheel was
      not repacked)
- [ ] the app's own MIT `LICENSE`

**No GPL anywhere in the payload:**

- [ ] `ffmpeg -version` on the **vendored** binary: `configuration:` contains
      `--enable-libmp3lame`, and contains **neither** `--enable-gpl` **nor**
      `--enable-nonfree` **nor** `--enable-version3`
- [ ] the vendored ffmpeg is not a Homebrew binary — check the configure line,
      not just `otool -L`
- [ ] CPython's bundled-dependency licence metadata reviewed: no GPL component,
      GNU readline in particular
- [ ] result of that review recorded, so the next release diffs against it rather
      than repeating it

**Attribution:**

- [ ] About / credits names ffmpeg, CPython, yt-dlp and QuickJS (or Deno), with
      the bundled versions
- [ ] the bundled yt-dlp version shown in About matches the wheel actually
      shipped

**Distribution:**

- [ ] no `.dmg`, no `.app`, no binary attached to a GitHub Release — only
      `yt_dlp-*.whl`, `extractor-manifest.json` and its signature

Generous upstream attribution is a brand value in this suite, not a legal chore.
This app is four other people's projects in a coat; the About screen should say
so.

---

## What would change the picture

Four changes, any one of which forces a relicense or a redesign. If a brief asks
for one of these, stop and escalate rather than implementing it:

1. **Enabling `--enable-gpl`** (or shipping a Homebrew ffmpeg) — the DMG becomes
   a GPL distribution and the app can no longer be described as MIT.
2. **Linking `libav*` in-process** instead of spawning `ffmpeg` — the
   process-boundary argument in §1 disappears and LGPL §6's relinking
   obligations apply directly to the app binary.
3. **Bundling a GPL PO-token provider** (deferred; see
   [`DEFERRED.md`](DEFERRED.md)) — same outcome as (1), reached through a plugin.
4. **A CPython build linked against GNU readline** — same outcome as (1),
   reached through the interpreter, and the only one of the four that could
   happen by accident.
