# Privacy Policy — Pitak

_Effective date: 2026-09-03 · Publisher: Parallel Line Foundation_

Pitak is a privacy-first, offline personal library catalogue. This policy
describes, in plain language, what the app does with your data. The short
version: **your data stays on your device, the app has no accounts, no
analytics, no advertising, and no tracking of any kind.**

## What Pitak stores on your device

- **Your library catalogue** (books, wishlist, covers, notes) in a database
  in the app's private storage. Never uploaded anywhere by itself.
- **Your borrowers vault** (borrower names/contact details and loans), if you
  use it, in a separate database encrypted with AES-256-GCM. It is unlocked
  by a passphrase you choose (strengthened with Argon2id). Your passphrase is
  never stored and never leaves the app. If you enable biometric unlock, a
  randomly generated vault-wrapping secret is kept in the Android Keystore /
  platform secure storage and released only after an on-device biometric
  check. Two honest limits: (1) while the app is open, an unlocked vault
  stays unlocked in memory until you lock it or the app exits — there is no
  automatic timeout; (2) the optional app-lock biometric gate is a screen
  cover, not a vault lock: it does not encrypt your data or lock an
  already-unlocked vault. Changing your passphrase re-wraps the same vault
  key; it does not rotate it, so old vault copies paired with an old
  passphrase could still be opened.
- **Settings** (theme, library name, sort preferences, and — if you fill them
  in — the contact details you choose to publish) in the app's private
  preferences store.
- **A GitHub access token**, only if you use the Publish feature, stored in
  platform secure storage (never in plain preferences).
- **A Google Books API key**, only if you add your own in Settings, stored in
  platform secure storage.

Uninstalling the app deletes all of the above from the device.

**Android system backup is switched off for this app.** Android normally copies
app data to your Google account (and to a new phone during setup). Pitak opts
out of both, so nothing above is copied anywhere by the operating system. To
move your library to another device, use the app's own Backup / Restore, which
produces a file you control.

## Permissions and why

- **Camera** — used only on screens you open deliberately: scanning ISBN
  barcodes to add books, and photographing book covers. Photos are processed
  and stored on-device.
- **Internet** — used only for the explicit actions listed below. The app
  makes no background or silent network connections.

## When anything leaves your device

Network activity happens only when you explicitly ask for it:

1. **ISBN lookup.** When you scan or type an ISBN and tap Lookup, that ISBN
   (and, if the first attempt finds nothing, its equivalent ISBN-10/ISBN-13
   form) is sent to Open Library (openlibrary.org), falling back to Google
   Books (googleapis.com), to fetch book metadata. Like every app, Pitak
   identifies itself to these services with a fixed "User-Agent" string
   naming the app and its source repository — no device or user identifier.
   If you have added your own Google Books API key in Settings, it is sent
   to Google with those requests (that is what the key is for). Nothing else
   is sent.
2. **Remote cover images** (optional, OFF by default). If you enable it in
   Settings, book covers are downloaded over https from a fixed allow-list of
   cover hosts. Your catalogue is never uploaded; only cover image files are
   fetched.
3. **Publish to web.** If you use Publish, a read-only viewer of your library
   is uploaded to a GitHub repository *you* own, via GitHub's device-flow
   sign-in. The permission you grant ("public_repo") is GitHub's narrowest
   available and covers *all* of your public repositories, not just the site;
   GitHub's own privacy policy applies to that account and to the traffic.
   The published site is **public to anyone on the internet** — including the
   library name, any contact details or event posters you enter under
   Publish, and the book covers. Before upload, Pitak redacts private fields
   (notes, location, source, lender details), and photos are re-encoded with
   EXIF metadata — including GPS coordinates — stripped. During publishing
   your device also downloads book covers from the same fixed cover hosts
   listed above and, afterwards, checks the public site URL once to confirm
   it is live. You can delete the published site at any time from GitHub.
   Signing out in the app forgets the token on your device; to revoke the
   app's access on GitHub's side, remove "Pitak" under GitHub → Settings →
   Applications (the app cannot do this for you).
4. **Exports and backups.** JSON/CSV/PDF exports and `.pitabak` backups are
   files the app hands to your device's share sheet; you choose where they
   go. Backups you restore are read locally and never transmitted. Note:
   `.pitabak` backups are **not fully encrypted** — the books, wishlist and
   cover images inside are stored plainly; only the borrowers vault (when
   you have one) remains encrypted inside the archive. Anyone who receives
   your backup file can read the catalogue fields, so share backups only
   with people you trust with that data.

## What Pitak does NOT do

- No accounts, no sign-in required for the app itself
- No analytics, crash beacons, advertising, or tracking SDKs
- No sale or sharing of your data with anyone (there is no "we" holding your
  data — the developer operates no servers for this app)
- No access to your contacts, files, location, microphone, or any data
  outside the app's own storage

## Children's privacy

Pitak is a general-audience utility and is not directed at children under 13.
It collects no personal information from anyone.

## Changes

Any change to this policy is committed to the app's source repository
(github.com/PLFIndia/pitak-x) with a new effective date, before the
corresponding app release.

## Contact

Questions about this policy or the app's data handling: open an issue at
github.com/PLFIndia/pitak-x/issues.
