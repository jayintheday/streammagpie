# StreamMagpie — terms of sale

Plain language, and short on purpose. These terms cover the **official
StreamMagpie build** sold on Gumroad. They do not cover the MIT source. Paste
this text into the Gumroad listing; this file is the copy of record.

## What you are buying

One purchase of the **official macOS build of StreamMagpie**: a Developer ID
signed, notarized DMG, with the audio tooling bundled inside it. Pay once. No
subscription, no account, no cloud.

You may install it on the Macs you use. Do not resell it, redistribute it, or
publish the DMG anywhere — including a GitHub Release. If someone else wants
StreamMagpie, they can buy the build or compile the source.

App updates are new file versions on Gumroad. Re-download from your library.
There is no in-app updater for the app itself, and no promise of a fixed release
schedule.

Extractor updates are different, and they are the point of the design: the
component that talks to YouTube can update itself quietly inside the app, so a
build you already own keeps working when YouTube changes.

## The source is free, and these terms do not cover it

StreamMagpie's source is public and **MIT licensed**
(<https://github.com/jayintheday/streammagpie>). MIT means what MIT means: clone
it, read it, change it, build it, ship your own thing from it. Nothing here
restricts that. These terms apply **only to the purchased binary**. If you
compile it yourself, MIT is the whole agreement and you can stop reading.

The app bundles other people's work — ffmpeg, CPython, yt-dlp, and a JavaScript
runtime — under their own licences, which travel inside the DMG.
[`docs/licensing.md`](licensing.md) has the details.

## YouTube and copyright

StreamMagpie runs on your Mac. It does not host videos. Downloading may violate
YouTube's terms. You are responsible for using it only with content you have the
right to copy (your uploads, Creative Commons, public domain, or other
permission). Do not use it to strip DRM or paid rental streams.

The tool is sold as software, not as a licence to anyone else's media.

That responsibility is yours and it does not transfer. Buying the app is not
advice that any particular download is lawful where you live, and no part of
these terms should be read as encouragement to breach an agreement you have with
someone else.

## No warranty, and the limit of what can be claimed

The software is provided **"as is", without warranty of any kind** — no promise
that it is free of defects, that it fits any particular purpose, or that any
given video will convert.

YouTube changes extraction without notice. We ship extractor updates as fast as
we reasonably can. **There is no guarantee a given video will convert on a given
day**, and that is a property of the problem rather than a defect we are
promising to remove.

To the fullest extent the law allows: **there is no liability for lost time,
lost files, or any indirect or consequential loss**, and total liability for any
claim relating to StreamMagpie is capped at **the amount you actually paid for
it**.

Some jurisdictions do not allow those exclusions. Where that is the case, the
exclusions are limited to what the law allows and nothing more.

## Refunds

Refunds are handled through Gumroad, under the refund policy stated on the
StreamMagpie product listing there. That listing is the authority; ask before
buying if it matters to you.

## Name and icon

The **StreamMagpie** name and icon identify the official product and are
reserved. MIT covers the software, not the branding. If you build and distribute
your own version of the source, **rebrand it** — a different name and a
different icon — so nobody is misled about what they installed or who supports
it.

## Support and requirements

Support is best effort, through the GitHub repository:
<https://github.com/jayintheday/streammagpie/issues>. Clear bug reports are
genuinely welcome. There is no SLA and no guaranteed response time.

StreamMagpie needs **macOS 14 or later on Apple silicon** and does not run on
Intel Macs. Check that before you pay — buying it will not help.

---

StreamMagpie is copyright © 2026 Vijay Patel. Source licensed under MIT; see
[LICENSE](../LICENSE).
