# Privacy Policy — Pitak

_Effective date: 2026-11-08 · Publisher: Parallel Line Foundation_

_Changed 2026-11-08 — new **Event alerts** (Android, item 10). Once you have
a saved library, Pitak explains them and asks; if you accept, it asks each
library you saved for its public events file about every 12 hours, also while
the app is closed, and notifies you about new or changed posters. Each of
those sites sees the scheduled requests. Item 10 says exactly which name a
notification shows, how your lock-screen setting affects it, and how long the
small bookkeeping file stays on the device._

_Changed 2026-11-06 — **Borrowed Items** adds maintainer-reviewed loan
reminders. Template text is plaintext on this device and is not in the current
backup. The generic share action hands the item title, due message and
sanitized cover to the OS share flow when you tap it; you then choose a target.
The separate WhatsApp action instead opens `wa.me` with the borrower's phone
number and rendered text. If a browser handles that link, those values can
reach Meta's `wa.me` service and browser history. No reminder message is sent
automatically (item 9)._

_Changed 2026-11-06 — **Restore from this site** can recover public catalogue
fields and covers from your own active hosting target into an empty catalogue.
It also restores the public fingerprint when available and carries it in later
backups. No new party is contacted and no private fields are recovered._

_Changed 2026-11-04 — a new optional Settings → Library switch can start an
ISBN lookup immediately after scanning. It is off by default; the ISBN goes
only to the same lookup services as a manual Lookup (item 1)._

_Changed 2026-11-04 — wording only: the site-check paragraph now distinguishes
Cloudflare's read-back from GitHub Pages' deferred proof. No new data is
collected, stored or sent._

_Changed 2026-11-02 — if you publish a site, the *Available / Not available*
tags on it now update by themselves shortly after you lend or return an item
(item 3; you can switch this off), and opening a saved library also requests
and saves its `availability.json` (item 5). The tags were already public;
they are just kept current. No borrower data is uploaded, and nothing new is
collected about you. Backups now also carry your website's publishing record
(item 7) — no passwords or tokens — so a restored phone does not upload every
cover again._

_Changed 2026-10-30 — wording only: the move paragraph now also says what
Cancel move and Finish without retiring leave public, and that reconnecting to
another Worker does not touch the previous one. No new data is collected,
stored or sent._

Pitak is a privacy-first, offline personal library catalogue. This policy
describes, in plain language, what the app does with your data. The short
version: **your data stays on your device, the app has no accounts, no
analytics, no advertising, and no tracking of any kind.**

## What Pitak stores on your device

- **Your library catalogue** (books, wishlist, covers, notes) in a database
  in the app's private storage. Never uploaded anywhere by itself.
- **Event-alert bookkeeping** (Android, item 10): which saved libraries are
  checked, a fingerprint of their last-seen posters and any alert not yet
  shown. Plain files in private storage, excluded from backups. They reveal
  which libraries you follow to anyone who can read the app's private
  folder (a rooted or compromised device), which is why they hold no more
  than that.
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
- **Reminder message templates** (your custom labels and three message bodies,
  plus the selected template ID) in that same private preferences store. They
  are **plaintext, not encrypted**, are not in the current `.pitabak` backup,
  and can contain anything you type, so do not include private details. Rendered
  reminders, recipients and share history are not stored.
- **A GitHub access token**, only if you use the Publish feature to publish to
  GitHub Pages, stored in platform secure storage (never in plain
  preferences).
- **A Cloudflare API token**, only if you connect Cloudflare Workers for
  publishing, stored the same way. It is created by you, scoped to one
  Cloudflare account, and limited to editing Workers scripts. Alongside it the
  app stores the account and Worker you chose and whether the address was
  verified; that whole record is treated as a secret and replaced as a unit,
  so a new token can never be paired with an old target.
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
  Core/update library and cannot run that check. On Android, event alerts
  (item 10) also use it on a schedule while the app is closed, if you leave
  them on.
- **Notifications** (Android 13+ asks you; older Android does not) — used
  only for event alerts (item 10). Pitak shows no other notifications.
- **Android system permissions merged by the scheduling library**
  (`ACCESS_NETWORK_STATE`, `RECEIVE_BOOT_COMPLETED`, `WAKE_LOCK`,
  `FOREGROUND_SERVICE`): they let the scheduled check wait for a network
  connection, survive a reboot and keep the device awake for the few seconds
  a check takes. Pitak runs no foreground service and reads no network
  details beyond "connected or not".

## When anything leaves your device

Network activity happens only when you explicitly ask for it, with three
exceptions: once you publish a site, Pitak keeps its *Available / Not
available* tags up to date by itself (item 3; on by default, switch in
Settings → Data); on Android, **event alerts** check the libraries you saved
about every 12 hours while the app is closed (item 10; offered on first use,
switch in Settings → Data); and the passive update check of Google Play
builds (item 8):

1. **ISBN lookup.** When you type an ISBN and tap Lookup — or scan one after
   enabling **Settings → Library → Look up ISBN after scanning** — that ISBN
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
   is uploaded to a site *you* control, on **one host at a time**: a GitHub
   repository you own, or a Cloudflare Worker in your own Cloudflare account.
   The published site is **public to anyone on the internet** — including the
   library name, any contact details or event posters you enter under
   Publish, the book covers, and which items are available (only *Available*
   or *Not available* — never who borrowed an item, how many copies are out
   or when they are due). **Availability updates automatically:** by default,
   shortly after you lend or return an item, Pitak uploads a small
   `availability.json` file to the same site. It lists only the public item
   keys (salted hashes that reveal no internal ID) of items whose every copy
   is lent out, plus the time of the change. This happens only while Pitak is
   open — nothing runs in the background — and a list that could not be sent
   yet waits on your device (it holds only those public keys and times). You
   can turn this off under Settings → Data; Pitak then deletes that file from
   your site. Before upload, Pitak redacts
   private fields (notes, location, source, lender details), and photos are
   re-encoded with EXIF metadata — including GPS coordinates — stripped. If
   you type GPS coordinates under Publish › Basic info, a separate opt-in
   switch controls whether they are published at all: "Not shared" (the
   default for new installations) publishes no coordinates anywhere;
   "Approximate" publishes them rounded to about 1 km; "Exact" publishes them
   as typed — both on your published page and in the machine-readable
   `library.json` descriptor that the library network reads.

   **GitHub Pages.** You sign in with GitHub's device flow. The permission you
   grant ("public_repo") is GitHub's narrowest available and covers *all* of
   your public repositories, not just the site; GitHub's own privacy policy
   applies to that account and to the traffic. You can delete the published
   site at any time from GitHub. Signing out in the app forgets the token on
   your device; to revoke the app's access on GitHub's side, remove "Pitak"
   under GitHub → Settings → Applications (the app cannot do this for you).

   **Cloudflare Workers.** You paste a Cloudflare API token that you create.
   The app opens Cloudflare's token-creation page with a template already
   scoped to one account and to "Workers Scripts · Edit", and verifies any
   token you paste before saving it. Pitak then calls only Cloudflare's API
   (`api.cloudflare.com/client/v4`) to read your account's `workers.dev`
   subdomain, open an upload session, upload the site's files and deploy them
   to the Worker you choose. A Pitak Worker is **dedicated to Pitak**: the
   first verification and every later publish replace the Worker's whole file
   set, so files you put there yourself are removed. Pitak creates only the
   public site files, its covers/posters folders and a small
   `pitak-publish.json` marker. Identical files are uploaded once, because the
   API accepts them by content hash — a file used in several places is a
   single upload — and Cloudflare's servers may keep uploaded file content
   even when a deployment does not complete. Cloudflare's API and its
   `workers.dev` edge see your device's IP address and the app's fixed
   User-Agent, as any web server does. The token stays on your device; Pitak
   cannot delete the Worker, so remove it in the Cloudflare dashboard if you
   stop using it, and delete the token there to revoke access. Before creating
   a new version the app turns the Worker's **version URLs** off and confirms
   it: while they are on, an older version of your site would itself be
   publicly readable under a different address. If that cannot be confirmed,
   publishing stops rather than exposing an older copy.

   **Checking the site and moving it.** After uploading, Pitak reads the site
   back from its public address to prove it serves the new files. On
   Cloudflare, a catalogue publish uses up to 12 cache-busted `books.json`
   requests, five seconds apart, and also reads the marker, `library.json` (or
   its absence), `events.json` and the poster files it just published. On
   GitHub Pages, a catalogue or events publish is proven afterwards by up to
   13 reads of `books.json` (or `events.json`) over about two and a half
   minutes after the commit: the first 30 s after it, then every 10 s. An
   automatic availability update is checked the same way: on GitHub Pages by
   reading `availability.json` up to 13 times over about two and a half
   minutes, on Cloudflare by reading the marker and `availability.json`. These
   are unauthenticated public requests to the site you published, never API
   calls that carry your token.

   You can also **move** a site from one host to the other. The new site is
   published and verified first; the old one then becomes a small "moved" page
   showing your library name and the new public address, and its catalogue
   data is deleted. Other Pitak phones never follow a move by themselves: they
   may show both addresses and change something only when their owner chooses.
   A printed library card keeps pointing at the old address until you reprint
   it.

   An interrupted move is never silent: the publish card keeps a banner until
   the move finishes, and the old site stays exactly as it is until it is
   verifiably retired. **Cancel** stops the move and leaves the copy already
   published on the other host online; **Finish without retiring** is offered
   only when Pitak can no longer sign in to the old site, and leaves that copy
   online too, unmarked. Pitak never deletes a site for you, so delete either
   copy at its host if you do not want it public. Reconnecting to a different
   Cloudflare Worker does not touch the previous Worker, which keeps serving
   exactly what it last served until you delete it in the Cloudflare dashboard.

   **Restoring from your own site.** After reinstalling, reconnecting the same
   hosting account and choosing **Restore from this site**, Pitak downloads
   `library.json` and `books.json` from that active site only. With your
   default-on cover consent it also downloads same-site cover images; turn the
   checkbox off to leave those references empty. Third-party cover links are
   kept but not fetched during restore (item 2 governs them later). The host
   sees your device's IP address and the app's fixed User-Agent, with no
   publishing token on these public reads. Restore works only into an empty
   catalogue and reports unreadable rows, duplicates and skipped covers. Notes,
   descriptions, locations, copy counts, page counts, added dates and loans are
   not on the site and cannot come back. The library name, map pin and hub lists
   must be re-entered. The public fingerprint is a label that helps readers
   avoid an identity conflict; it does not prove ownership. Your hosting
   account is the real publishing boundary, so protect it with a unique
   password and two-factor sign-in. Backups made afterwards carry that public
   fingerprint as plain JSON; the restore inspection says when a backup will
   adopt it. A well-formed fingerprint in a crafted backup is not proof that it
   belongs to you, so restore only backups you trust.
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
   Pitak: requests for `books.json` and the optional `events.json` and
   `availability.json` (which items are lent out, as Available / Not
   available) happen only when you tap, and only to that library's own site
   directory (a redirect
   to another host or library is refused), with the fixed User-Agent and
   "no-cache" hint. The site sees your device's IP address for each request.
   Pitak keeps one **saved copy** of each library's `books.json`,
   `events.json` and `availability.json` in the app's cache folder (never in backups — neither the
   phone's nor Pitak's `.pitabak`). Every time you open the library, Pitak
   first asks the site whether the file changed, sending the short fingerprint
   (the "ETag") the site gave with the saved copy; an unchanged file is not
   downloaded again. A site that runs its own server code could use that
   fingerprint to recognise a returning device even after its IP address
   changes; GitHub Pages sites cannot choose it. When the site can't be
   checked, the saved copy is shown with a note saying how old it is. Saved
   copies take at most 200 MB together (the least recently opened library is
   removed first), and a library's copies are deleted when you remove it from
   your saved libraries. The viewer itself never refreshes in the background;
   the separate event-alert check (item 10) reads only `events.json`.
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
   go. Backups you restore are read locally and never transmitted. To
   restore, the app makes a private temporary copy of the backup file you
   choose, inside its own storage where no other app can read it, and
   removes that copy again: when the restore has succeeded, when you choose
   another file or leave the Restore screen, or at the next start of the
   app. Note:
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
   recognisable to your hubs. If you publish a website, the backup also
   carries its publishing record as plain JSON (`publish_state.json`): the
   random code that makes your published cover file names (it hides internal
   item numbers), which site you publish to (the GitHub repository, or the
   Cloudflare account ID, Worker name and address), which files Pitak put
   online with their content fingerprints, and which cover each published
   picture came from (a file name on your phone or the public cover web
   address). It never contains your GitHub or Cloudflare sign-in, tokens or
   passwords. A restored phone uses it only if it has not published a site
   itself. Anyone who receives your backup file can read
   those fields, so share backups only with people you trust with that data.
   Restoring writes the new catalogue, covers and vault into a fresh
   app-private folder and switches to it in one step; the previous folder is
   deleted after a successful switch, and a half-built folder is removed on
   the next launch. If the system refuses one of those deletes, Pitak retries
   it at the next launch rather than reporting the restore as failed, so no
   second copy of your data lingers on the device.
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
9. **Loan reminders.** On Borrowed Items, tapping the WhatsApp/reminder action
   prepares the item title, due message and a sanitized local cover, then opens
   the generic OS share flow. You choose WhatsApp or another target and the
   conversation, review or edit the content, and decide whether to send it.
   Pitak does not select a recipient for the generic share, detect WhatsApp,
   send automatically, or treat a share hand-off as delivery. A separate
   WhatsApp icon appears when a phone number is available: it opens the
   borrower's `wa.me` conversation with only the rendered text prefilled,
   without reading the cover. When WhatsApp handles the link, you still tap
   Send. If WhatsApp is absent or does not handle the link, a browser may open
   it instead; in that case the phone number and rendered text are sent to
   Meta's `wa.me` web service and may be retained in browser history. Pitak
   does not detect WhatsApp or claim that this fallback keeps the data local.
   Blank or remote-only covers lead to an optional text-only share; Pitak does not
   download a cover just for a reminder. Local images are re-encoded to strip EXIF/GPS metadata, and a
   missing, unsafe, oversized or corrupt local file blocks image sharing rather
   than silently sending raw bytes. The `share_plus` plugin writes a temporary
   cover file in its app-cache directory during sharing; the OS/plugin or a
   later Android share removes it. Pitak keeps no reminder history or
   app-owned persistent reminder copy.
10. **Event alerts (Android only; on by default after you accept the
    explanation).** The first time you have a saved library, Pitak explains
    this feature and asks; on Android 13+ the system then asks for the
    notification permission. If you accept, about every 12 hours — including
    while the app is closed, and on mobile data — Pitak asks each library you
    saved yourself (by address or by card; never libraries it merely
    discovered) for its public `events.json`, under the same site-directory,
    HTTPS and redirect rules as item 5, with the fixed User-Agent and no
    cookies or credentials. Each site sees your device's IP address for that
    request, and — because the request repeats on a schedule — can infer that
    a device follows that library. When a poster appears or its caption
    changes, Pitak shows a notification with the poster's public caption. The
    title is the library's name as saved in Pitak, used only after Pitak has
    confirmed that library's own site (a successful refresh, or a card scan
    whose fingerprint matched the site); otherwise the title is the generic
    "New event at a saved library". A refresh replaces the saved name with the
    one the library publishes in its `library.json`. One exception: if you
    saved a library by address under a name you typed and then scanned its
    card, your typed name is kept and can appear as the title until the next
    successful refresh. Alerts are marked private: on a locked phone Android
    hides their text only if your lock-screen setting hides sensitive
    notification content; if it shows all notification content, the library
    name and caption are visible on the lock screen. The first check of a
    library only records what is there; it never alerts about posters that
    already existed. Removed posters are not
    announced. Pitak cannot tell when an image file was replaced under the
    same name. Timing is best effort: Android may delay or skip checks under
    battery saving, Doze or manufacturer restrictions, and a check never runs
    after you force-stop the app until you open it again. Turn alerts off at
    any time in **Settings → Data → Event alerts**; turning them off cancels
    the schedule and removes Pitak's alerts from the shade. Blocking Pitak's
    notifications in Android settings has the same effect the next time the
    app runs. What Pitak keeps for this: a small file with the addresses of
    the libraries it checks, a fingerprint of the posters it last saw, the
    site's `ETag`, and any alert not yet shown — in the app's private storage,
    excluded from backups. Only the background check updates this file, so
    it is not erased the moment you act: turning alerts off or resetting them
    leaves it as it is until a check runs again with alerts on (after a reset
    Pitak starts fresh and ignores what it saw before), and a removed
    library's entry is dropped at the next check — if no saved library is
    left, no check runs and the entry stays. Clearing Pitak's storage in
    Android settings, or uninstalling the app, deletes it. No history of
    shown alerts is kept.

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
