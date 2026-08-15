# Privacy Policy — Pitak

_Effective date: 2026-08-15 · Publisher: Parallel Line Foundation_

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
  check.
- **Settings** (theme, library name, sort preferences) in the app's private
  preferences store.
- **A GitHub access token**, only if you use the Publish feature, stored in
  platform secure storage (never in plain preferences).

Uninstalling the app deletes all of the above from the device.

## Permissions and why

- **Camera** — used only on screens you open deliberately: scanning ISBN
  barcodes to add books, and photographing book covers. Photos are processed
  and stored on-device.
- **Internet** — used only for the explicit actions listed below. The app
  makes no background or silent network connections.

## When anything leaves your device

Network activity happens only when you explicitly ask for it:

1. **ISBN / title lookup.** When you scan or type an ISBN (or search a
   title), that ISBN/title is sent to Open Library (openlibrary.org), falling
   back to Google Books (googleapis.com), to fetch book metadata. Nothing
   else is sent.
2. **Remote cover images** (optional, OFF by default). If you enable it in
   Settings, book covers are downloaded over https from a fixed allow-list of
   cover hosts. Your catalogue is never uploaded; only cover image files are
   fetched.
3. **Publish to web.** If you use Publish, a read-only viewer of your library
   is uploaded to a GitHub repository *you* own, via GitHub's device-flow
   sign-in (permission scope: public repositories only). Before upload, Pitak
   redacts private fields (notes, location, source, lender details), and
   photos are re-encoded with EXIF metadata — including GPS coordinates —
   stripped. You can delete the published site at any time from GitHub.
4. **Exports and backups.** JSON/CSV/PDF exports and `.pitabak` backups are
   files the app hands to your device's share sheet; you choose where they
   go. Backups you restore are read locally and never transmitted.

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
