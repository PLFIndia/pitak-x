# Privacy Policy — Pitak

_Effective date: 2026-10-25 · Publisher: Parallel Line Foundation_

Pitak is a privacy-first, offline personal library catalogue. This policy
describes, in plain language, what the app does with your data. The short
version: **your data stays on your device, the app has no accounts, no
analytics, no advertising, and no tracking of any kind.**

## What Pitak stores on your device

- **Your library catalogue** (books, wishlist, covers, notes) in a database
  in the app's private storage. Never uploaded anywhere by itself.
- **Your borrowers vault** (borrower names/contact details and loans), if you
  use it, in a separate SQLCipher-encrypted database. Argon2id strengthens
  your chosen passphrase into a key-encryption key, and AES-256-GCM uses that
  key to wrap the vault key. It is unlocked by your passphrase. Your
  passphrase is
  never stored and never leaves the app. If you enable biometric unlock, a
  randomly generated vault-wrapping secret is stored only in encrypted form,
  under a key inside your phone's secure hardware (Android Keystore) that the
  operating system will use only immediately after you pass a strong
  biometric check (fingerprint or Class 3 face unlock — a PIN cannot stand
  in). Adding or removing a fingerprint or face destroys that key, so
  biometric unlock switches itself off and you re-enable it with your
  passphrase. Two honest limits: (1) while the app is open, an unlocked vault
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
- **Internet** — used for the actions listed below. Google Play builds also
  check for updates on launch and, after you accept Play's update dialog,
  download in the background (item 7); the F-Droid flavor has no Play
  Core/update library and cannot run that check.

## When anything leaves your device

Network activity happens only when you explicitly ask for it, with one
passive exception (item 8, Google Play builds only):

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
   Settings, a book whose cover is a web link is downloaded **once**, over
   https, from a fixed allow-list of cover hosts: Open Library
   (covers.openlibrary.org), the Internet Archive that stores many of
   Open Library's covers (archive.org and its `ia….us.archive.org` storage
   nodes, reached only by following Open Library's own redirect), and Google
   Books (books.google.com, books.googleusercontent.com). A link to any other
   host is never contacted and simply shows no cover, and a redirect to any
   other host is refused. These hosts see your device's IP address for that
   one request, as any web server does. The downloaded image is then stored
   on your device exactly like a photo you took yourself — it becomes part of
   your library, is included in backups, and no request is made for that book
   again. Your catalogue is never uploaded; only cover image files are
   fetched. A cover you photographed yourself is never replaced by a
   downloaded one. The same switch also governs covers and event posters in a saved
   library's published viewer; those are memory-only and are covered in
   item 5.
3. **Publish to web.** If you use Publish, a read-only viewer of your library
   is uploaded to a GitHub repository *you* own, via GitHub's device-flow
   sign-in. The permission you grant ("public_repo") is GitHub's narrowest
   available and covers *all* of your public repositories, not just the site;
   GitHub's own privacy policy applies to that account and to the traffic.
   The published site is **public to anyone on the internet** — including the
   library name, any contact details or event posters you enter under
   Publish, and the book covers. Before upload, Pitak redacts private fields
   (notes, location, source, lender details), and photos are re-encoded with
   EXIF metadata — including GPS coordinates — stripped. If you type GPS
   coordinates under Publish › Basic info, a separate opt-in switch controls
   whether they are published at all: "Not shared" (the default for new
   installations) publishes no coordinates anywhere; "Approximate" publishes
   them rounded to about 1 km; "Exact" publishes them as typed — both on your
   published page and in the machine-readable `library.json` descriptor that
   the library network reads. During publishing your device also downloads
   book covers from the same fixed cover hosts listed above and, afterwards,
   makes up to 12 cache-busted `books.json` requests, five seconds apart, to
    verify that the public site serves the bytes just published. You can delete the
   published site at any time from GitHub. Signing out in the app forgets the
   token on your device; to revoke the app's access on GitHub's side, remove
   "Pitak" under GitHub → Settings → Applications (the app cannot do this
   for you).
4. **Library network — Refresh.** The Library network screen keeps the list
   of other Pitak libraries you save (by web address, or by scanning a
   library's card in person). Nothing about it leaves your device until you
   tap Refresh; Refresh then downloads the `library.json` descriptor from
   each saved site — only from GitHub Pages, Cloudflare Pages or Cloudflare
   Workers addresses that the app validated when you saved them — to update
   names, optional map pins and hub/member links. When a saved library appears
   to have moved to another address, both addresses are shown and only your
   explicit choice changes anything. A downloaded descriptor can itself list other
   libraries (a hub's members, or the hubs a library belongs to); Refresh
   also fetches the descriptors of those libraries, even though you never
   saved them yourself, so that they can appear in your list and on the map.
   This follows links at most two steps away from a library you saved, only
   to the same validated kinds of address, and stops at 500 libraries per
   run. Every site contacted — saved or discovered — sees your device's IP
   address for that one request, as any web server does. Refresh runs only
   when you ask for it; there is no background polling. If you used the old
   bookmarks feature, its entries move into this list automatically the first
   time you open the screen — that move happens entirely on your device.
5. **Opening a saved library's published catalogue.** Tapping a library in
   Library Bookmarks or Library network opens its catalogue and events inside
   Pitak: requests for `books.json` and optional `events.json` happen only
   when you tap, and only to that library's own site directory (a redirect
   to another host or library is refused), with the fixed User-Agent and
   "no-cache" hint. The site sees your device's IP address for each request.
   `books.json` and `events.json` are never stored on your device: leaving
   the screen discards both snapshots; opening the library again fetches them.
   There is no background refresh, cached copy or offline mode.
   Covers and event posters are SEPARATE requests and obey the
   remote-cover switch in item 2: with it off (the default) the viewer
   shows placeholders and offers a Load covers button; with it on, images load
   only while you view — covers come either from the library's `covers/…`
   files or the fixed cover hosts in item 2; posters come only from the
   library's `posters/…` files — all under the same directory rule and held in
   memory only. They are not added to your library, backups or device storage,
    and they disappear when you leave.
   Viewing a public catalogue never changes your own catalogue, your saved
   libraries or their fingerprints.
6. **Network map** (optional, off until you allow it). The first time you
   open the Library network › Map tab, the app asks before showing the map.
   If you accept, map images are downloaded from OpenStreetMap
   (tile.openstreetmap.org) while the map is open — OpenStreetMap's servers
   see your device's IP address and the map area you view, as any web server
   does, and the app identifies itself with the same User-Agent string as
   everywhere else. Declining keeps the list view, which works fully offline;
   you can change your mind later in Settings. The map never sends your list
   of libraries anywhere.
7. **Exports and backups.** JSON/CSV/PDF exports and `.pitabak` backups are
   files the app hands to your device's share sheet; you choose where they
   go. Backups you restore are read locally and never transmitted. Note:
   `.pitabak` backups are **not fully encrypted** — books, magazine titles and
   issues, other items, wishlist and cover images inside are stored plainly;
   only the borrowers vault and its wrapped key blob remain encrypted inside
   the archive. `item_kinds.json` records the stable UID and kind of every non-book
   item (an unlisted UID means a book). `periodicals.json` contains full
   magazine-series records and issue details, including subscription dates,
   notes, physical location, source, addedBy/addedDate, removal metadata and
   bound-volume end dates. The backup
   also carries your library identity (library name and ID) and your
   saved-libraries list as plain, unencrypted JSON, so a restored phone stays
   recognisable to your hubs. Anyone who receives your backup file can read
   those fields, so share backups only with people you trust with that data.
   Restoring writes the new catalogue, covers and vault into a fresh
   app-private folder and switches to it in one step; the previous folder is
   deleted immediately after a successful switch (and any half-built folder
   is removed on the next launch), so no second copy of your data lingers on
   the device.
8. **Update check (Google Play builds only).** When the app starts, the
   Play-distributed build asks the Google Play Store whether a newer version
   of Pitak is available for the flexible flow, Play shows its update dialog;
   after you accept, the Store downloads in the background and the app offers
   a restart
   once it is ready. The query
   is made by Google's Play Store component — which installed the app and
   already knows its package name and version — and Pitak itself sends
   nothing: no catalogue data, no identifiers, no server of its own is
   involved. The F-Droid flavor has no Play Core/update library, so the check
   cannot run there (F-Droid's own client handles updates).

## What Pitak does NOT do

- No accounts, no sign-in required for the app itself
- No analytics, crash beacons, advertising, or tracking SDKs
- No sale or sharing of your data with anyone (there is no "we" holding your
  data — the developer operates no servers for this app)
- No access to your contacts, microphone, or device location sensors
- No broad or shared-storage access: Pitak reads only files or images you
  explicitly choose (for example imports, merges, backup restores, event
  posters and the library logo); exports and backups go through the OS share
  sheet to a destination you choose

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
