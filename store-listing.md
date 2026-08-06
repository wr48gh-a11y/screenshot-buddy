# Screenshot Buddy App Store Listing

**App Store Connect is authoritative, not this file.** This is a mirror of what is actually
live, kept under version control so changes are reviewable and so drift is visible.

That distinction is not academic. Until 2026-08-06 this file recorded a subtitle and a
description that had never been submitted; the copy actually live had diverged. The live
subtitle read "Stop digging through Finder", which this file never mentioned, and that is what
drew the Guideline 5.2.5 rejection. Nobody could see the problem by reading the repo.

**When you change copy in App Store Connect, update this file in the same sitting.**

Character limits are noted where Apple enforces them.

---

## App name (30 char max)
`Screenshot Buddy`

## Subtitle (30 char max)
`Stop digging through folders`

*(28 chars. Keep Apple product names out of the subtitle entirely. It is indexed marketing
copy, and a referential trademark use will not be read charitably there, whatever the
[Apple trademark guidelines](https://www.apple.com/legal/intellectual-property/guidelinesfor3rdparties.html)
allow in body text.)*

## Price
**$2.99** (one-time purchase, Tier 3). Enroll in the **Small Business Program** (free) for the 15% commission rate instead of 30%. Consider a launch discount to $0.99 for the first week to seed reviews. Price is changeable any time in App Store Connect.

## Category
- **Primary:** Utilities
- **Secondary:** Productivity

## Age rating
4+ (no objectionable content)

---

## Promotional text (170 char max, editable any time without review)
Your screenshots folder is a mess. Screenshot Buddy puts it in your menu bar, so any shot is one click away and the whole pile is gone in one more.

---

## Description

Your screenshots folder has two hundred files in it and you need the one from four minutes ago. Screenshot Buddy puts that folder in your menu bar, so any shot is one click away, and the whole pile is gone in one more.

It doesn't take screenshots. macOS already does that. Screenshot Buddy looks after the folder they land in.

If you build with AI coding agents, you know why this app exists: check the terminal, screenshot it. Something breaks, screenshot it. Paste it back in so the agent can see what you see. Do that fifty times a day and the folder turns into a mess. You don't have to be a developer to feel it, though: anyone whose screenshots have piled up for two years knows the same problem.

Point Screenshot Buddy at the folder where your screenshots land (usually your Desktop) and every file in it shows up as a thumbnail, newest first, labeled by when you took it: "4 minutes ago," not "Screenshot 2026-07-30 at 14.22.31."

WHAT YOU CAN DO WITH A SHOT

Press Space for a full-size preview, arrow keys to flip through the rest
Drag it straight into an email, a doc, or your coding agent's chat
Rename it in place, right in the grid
Right-click to open it, or reveal it in its folder
Move a single file to the Trash without touching the rest

WHEN IT PILES UP
Sweep to Trash clears the folder in one click. Everything stays recoverable from the macOS Trash, the normal way. Delete Forever skips the Trash when you want the space back sooner, and gives you a few seconds to undo it. Either way, the button shows you how much the folder is holding before you press it.

GOOD TO KNOW
Screenshot Buddy works with image files: PNG, JPEG, HEIC, TIFF, GIF, BMP, and WebP. It watches one folder at a time. Screenshots is the obvious choice, but any folder of images works, and you can change it whenever you like.

ONE PURCHASE, NO SUBSCRIPTION
Buy it once and it's yours. No monthly fee, no yearly renewal to forget about, no ads, ever.

PRIVATE BY DESIGN
Everything happens on your Mac. No account, no sign-in, no tracking, nothing sent anywhere. Screenshot Buddy only reads the one folder you point it at.

Screenshot Buddy is a menu bar app. After you connect a folder, look for its icon at the top right of your screen.

---

## Keywords (100 char max, comma-separated, no spaces after commas)
`clean,cleaner,clutter,delete,trash,folder,disk,space,storage,tidy,sweep,developer,coding,images,png`

*(99 chars. Never repeat a word Apple already indexes from the app name or the subtitle, since
that budget is wasted. Covers both audiences: the general "clean up my Mac" searcher (clean,
clutter, tidy, storage) and the "I use AI coding tools" searcher (developer, coding).)*

---

## What's New (for version 1.0)
First release. Screenshot Buddy keeps your screenshots folder spotless from the menu bar.

---

## App Privacy (nutrition label answers)
- **Data collection:** None. Answer "No, we do not collect data from this app."
- No tracking, no analytics, no third-party SDKs.

---

## URLs (LIVE, hosted on GitHub Pages)
- **Privacy Policy URL:** https://wr48gh-a11y.github.io/screenshot-buddy/privacy.html
- **Support URL:** https://wr48gh-a11y.github.io/screenshot-buddy/support.html
- **Marketing URL (optional):** https://wr48gh-a11y.github.io/screenshot-buddy/

Source lives in `docs/`; edit and push to update. First deploy can take a couple of minutes.

---

## Copyright
2026 Hugh Southall

---

## Apple trademarks: what goes where

The 2026-08-06 rejection cited Guideline 5.2.5. What survived and what did not:

- **Out of all metadata:** "Finder", "Quick Look". Metadata includes the **screenshots**, which
  had these rendered into the images. `marketing/gen.py` is the source for those, so fix the
  captions there and regenerate rather than editing the PNGs.
- **Fine in body copy:** "macOS", "Mac", "Trash", "Desktop". These name the platform and its
  ordinary furniture accurately; they are not standing in for a product identity.
- **Left alone in the app itself:** the "Show in Finder" menu item. The rejection was scoped to
  metadata, that is the accurate name of the system function being called, and renaming it
  would make the app harder to understand.
