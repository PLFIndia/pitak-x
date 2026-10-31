# Mockup — "How Pitak works" (information page in the drawer)

> **Status: approved and implemented; verified against branch `appViewer`,
> 2026-10-25. Updated 2026-10-30:** three guides added at the maintainer's
> request — **Wishlist: books to buy**, **Set up Cloudflare Workers** (what
> the Cloudflare setup asks for and where to find each value) and **Events and
> posters** — and the publish guide's Cloudflare part now points to the new
> guide. This file is the design and copy record; the copy the app ships is
> `lib/features/guides/domain/catalog/*.dart` (grouped by topic), in the order
> set by `lib/features/guides/domain/guide_catalog.dart` — edit both together.
> The nine guides below follow the shipped catalog order. The “Facts behind
> the copy” section lists the code behind each claim.
>
> Markdown italics render as plain text in the app; inline markup supports only
> `**bold**` and `` `code` ``. Every card opens a separate guide page and every
> guide ends with its destination button. All nine guides are included; none is
> optional.

Goal: a librarian who has never used GitHub, never heard of "JSON" and does
not want to read a manual can follow each guide top-to-bottom in under a
minute. Rules used for the copy:

- one screen per topic, nothing scrolls more than ~1.5 screens on a phone;
- numbered steps, one action per step, bold = the exact button/menu label;
- "Good to know" = at most 3 short bullets, only things that avoid a mistake;
- no jargon without a 6-word explanation the first time ("repository");
- every guide ends with a button that opens the screen it just described.

---

## 1. Where it lives (drawer)

```
┌──────────────────────────────┐
│ [logo]  Kadugodi Library     │
├──────────────────────────────┤
│ 🔒  Borrowers vault          │
│ ☁️   Publish to web           │
│ 🔖  Wishlist                 │
│ 📰  Magazines                │
│ ⬡   Library network          │
│ ↗   Share Library Website    │   (only once published)
│ ❔  How Pitak works          │
├──────────────────────────────┤
│ ⚙   Settings                 │
└──────────────────────────────┘
```

The primary destinations scroll; Settings stays pinned at the bottom. How
Pitak works remains in the primary list.

## 2. Page layout

**Page: "How Pitak works"** — a short intro line and nine cards. Tapping a
card opens that guide as its own page (not an accordion: an open accordion
pushes the other topics off-screen, and a page gets a back button + a deep
link button at the bottom).

```
┌──────────────────────────────────────┐
│ ←  How Pitak works                   │
├──────────────────────────────────────┤
│ Short guides, one per job. Each ends │
│ with a button to the right screen.   │
│                                      │
│ 📚 Books, magazines and other items  │
│    Three kinds of item, one library  │
│    — which form to use               │
│ 🔖 Wishlist: books to buy            │
│    Note the books you want; add one  │
│    to the library when it comes      │
│ ☁️ Put your catalogue online         │
│    A free public web page of your    │
│    books — on GitHub or Cloudflare   │
│ 🔑 Set up Cloudflare Workers         │
│    The other free host — what to     │
│    type and where to find it         │
│ 📣 Events and posters                │
│    Announce story hours, sales and   │
│    meetings on your web page         │
│ 📍 Put your library on the map       │
│    Let nearby libraries find you —   │
│    you choose how exact              │
│ 💾 Backup, restore, export, import   │
│    Which one when                    │
│ 🔒 Lending and the borrowers vault   │
│    Who borrowed which item, when it  │
│    is due — encrypted on this phone  │
│ ⬡ Hubs, members and library cards    │
│    Your list of other Pitak          │
│    libraries — and what a hub is     │
└──────────────────────────────────────┘
```

**Guide page anatomy** (same skeleton for all nine):

```
┌──────────────────────────────────────┐
│ ←  Put your catalogue online         │
├──────────────────────────────────────┤
│ One sentence: what this does.        │
│                                      │
│ You need:  [GitHub account] [Internet]   ← chips, optional
│                                      │
│ ① Step — one action, bold label      │
│ ② Step                               │
│ …                                    │
│                                      │
│ Good to know                         │
│ • bullet                             │
│ • bullet                             │
│                                      │
│ [ Open Publish to web → ]            │   ← FilledButton, deep link
└──────────────────────────────────────┘
```

---

## 3. Copy

### 3.1 Books, magazines and other items

Card subtitle: *Three kinds of item, one library — which form to use*.

**Intro.** Your library holds three kinds of item: **books**, **magazine
issues** (grouped under their magazine title) and **other items** — a DVD, a
board game, a map. One list, one search, one way of lending; the kind only
decides which form you fill in.

| I want to… | Use |
|---|---|
| Add a book | **+** → **Add book**, or **Scan to add** its barcode |
| Add a magazine | **+** → **New magazine title** once, then **Add magazine issue** per issue |
| Add something else | **+** → **Add other item**; describe it in **Description** |

**Catalogue a magazine**

1. On the Library screen tap **+**, then **New magazine title**.
2. Type the title (ISSN, publisher and frequency are optional) and tap
   **Add magazine title**.
3. Open **☰ → Magazines**, tap the magazine, then **Add issue**.
4. Type the **Issue number** or pick a **Cover date**; **Title preview**
   shows the name the issue will get.
5. Tap **Add issue**. The issue is listed under its magazine and in the
   Library.

**How magazines behave**

- An issue takes its title, publisher and language from its magazine title;
  edit the title once and every issue follows.
- **Bound volume** (a switch on the issue form): several issues bound as one
  physical item, identified by its first and last issue dates. One item, one
  loan.
- **Track subscription** on a magazine title makes the **Magazines** list
  warn **Expiring soon** 30 days before the end date, then **Lapsed**.

**The same for every kind**

- Lend any item — a book, an issue, a board game — with **Lend** on its page.
- The chips **Books**, **Magazines**, **Others** show one kind; tap again for
  everything. Search reads notes too, so a **Description** is searchable.
- Backups, exports, merges and your published page carry every kind.

**Good to know**

- An item keeps its kind — a book cannot later become a magazine issue.
  **Delete permanently**, then add it again with the right form.
- A magazine title cannot be deleted while it still has issues; delete those
  first.
- An other item's **Description** stays on this phone; the published page
  shows only its title, cover, language and age group.

`[ Open Magazines → ]`

---

### 3.2 Wishlist: books to buy

> **Added 2026-10-30.** Labels checked against `wishlist_page.dart`,
> `add_wishlist_page.dart` and `wishlist_detail_page.dart`.

Card subtitle: *Note the books you want; add one to the library when it comes*.

**Intro.** The wishlist is your shopping list: books you want for the library
but do not have yet. It is kept apart from your catalogue, and it never
appears on your web page.

**Add a book you want**

1. Open **☰ → Wishlist** and tap **+**.
2. Type the **Title**. Know the ISBN, or have the book in hand? Type the
   **ISBN** or tap the barcode button (**Scan barcode**), then tap the
   magnifier (**Look up details**) to fill in the rest.
3. Optional: choose a **Priority** (Low, Medium or High) and add a **Price
   estimate** or **Notes**.
4. Tap **Add**.

**When the book arrives**

1. Open **☰ → Wishlist** and tap the book.
2. Tap **Purchased — add to library**. Pitak adds it to your catalogue and
   moves it to the **Purchased** list at the bottom of the wishlist.

**Good to know**

- **Mark as purchased only** records that you bought it but adds nothing to
  your catalogue.
- A book whose ISBN is already in your library is not added twice — Pitak
  only marks the wish as purchased.
- Scanning only reads the barcode. Pitak goes online only when you tap
  **Look up details**.

`[ Open Wishlist → ]`

---

### 3.3 Put your catalogue online

> **Updated 2026-10-28 (S10):** the shipping guide documents **two hosts** —
> GitHub Pages and Cloudflare Workers — because the app publishes to one
> active host, not to GitHub alone. **Updated 2026-10-30:** the Cloudflare
> setup details moved to their own guide (§3.4); this one points to it. This
> section mirrors `catalog/publishing_guides.dart`; the HTML mockup next to
> this file is a frozen 2026-10-19 design artefact.

**Intro.** Pitak can turn your book list into a simple public web page that
anyone can open and search. It is free: on **GitHub Pages**, or on
**Cloudflare Workers** in your own account — one address at a time.

**You need:** a free GitHub account (github.com), or a free Cloudflare account
(dash.cloudflare.com).

**What goes online:** titles, authors, covers, and — if your vault is
unlocked when you publish — whether a book is available.
**Never goes online:** borrowers, loans, notes, shelf locations.

**First time on GitHub Pages**

1. Open **☰ → Publish to web**.
2. Tap **Sign in to GitHub**. Pitak shows a short code.
3. Open the link shown (github.com/login/device) — on this phone or on a
   computer — log in to GitHub and type the code. Come back to Pitak; it
   continues by itself.
4. Tap **Set up a repository**, give it a short name like `my-library`, tap
   **Create** — that folder is where your page lives.
5. Tap **Publish catalogue now**.
6. Your web address appears under **Your site**. Tap **Copy link** or
   **Share**. The first time, the page can take a minute or two to go live.

**Or use Cloudflare Workers**

On **Publish to web**, tap **Connect Cloudflare** on the Cloudflare Workers
card. Cloudflare needs a few more details than GitHub: a token (a password
just for Pitak), your account, your `workers.dev` name and a name for your
site. The next guide, **Set up Cloudflare Workers**, explains each one and
where to find it.

**Give the Worker to Pitak alone:** every publish replaces everything already
on it, so publish from one phone at a time. Pitak calls the site live only
after it reads the published files back. Moving into a Worker that already
holds a test page or another copy asks first, and the button says **Replace
and move**.

**Every time after that**

Added or lent books? Open **Publish to web** and tap **Publish catalogue
now** again. Only what changed is uploaded, so it takes seconds. It publishes
to whichever host is active. When Pitak only checks an earlier publish, the
message says **Verified** — nothing new was published.

**Moving to the other host later**

You can move the page between the two hosts. Pitak verifies the new site
first, then turns the old address into a short "moved" page. If that last step
cannot finish, the publish page keeps three choices: Retry move, Skip
retirement (only when the old site is really gone) and Cancel move (which
keeps your current site and leaves the new copy online until you delete it).
If Pitak cannot sign in to the old site at all, Finish without retiring
replaces Skip behind a stronger warning — that copy also stays online. Other
phones never follow a move by themselves — they may offer the choice to their
owner — and a printed library card still shows the old address, so reprint it
after a move.

**Good to know**

- The **Basic info** tab adds your library's name, address, email and phone
  to the page. Every field is optional.
- Signing out of GitHub does not take your page down. Disconnecting
  Cloudflare only forgets the token — it never deletes the Worker.
- Sign-in not finishing? Keep the code screen open and type the code in a
  browser on a computer instead.

`[ Open Publish to web → ]`

---

### 3.4 Set up Cloudflare Workers

> **Added 2026-10-30.** The publish guide could only *name* what Cloudflare
> asks for; readers also need to know what each value is and where to get it.
> Pitak's labels are checked against `cloudflare_token_dialog.dart`,
> `cloudflare_name_dialogs.dart`, `cloudflare_verification_dialog.dart` and
> `cloudflare_tile.dart`. Cloudflare's own labels (**Workers & Pages**,
> **Account details**, **Your subdomain**, **Continue to summary**, **Create
> Token**) come from Cloudflare's documentation (checked 2026-10-30) and can
> change with its dashboard.

Card subtitle: *The other free host — what to type and where to find it*.

**Intro.** Cloudflare can hold your public catalogue for free, instead of
GitHub Pages. Your site lives in a "Worker": one small website in your
Cloudflare account. Setting it up takes about ten minutes, once.

**You need:** a free Cloudflare account (dash.cloudflare.com).

**What Pitak will ask you for**

- **Cloudflare API token** — a secret code, like a password just for Pitak.
  It can only update your website. You create it on Cloudflare's website
  (steps below).
- **Your account** — Pitak lists it; tap it. Asked for an **Account ID**
  instead? In Cloudflare open **Workers & Pages** and copy it from **Account
  details** (32 letters and numbers).
- **workers.dev subdomain** — your account's part of the address:
  `asha-books` in `asha-books.workers.dev`. If Pitak asks for it, find it in
  Cloudflare under **Workers & Pages**, next to **Your subdomain**; type only
  the part before `.workers.dev`.
- **Worker name** — a name you make up for your site, like `library`, giving
  `library.asha-books.workers.dev`. Use lower-case letters, numbers and
  hyphens (-), no hyphen at either end.

**Create the token (in your browser)**

1. Open **☰ → Publish to web** and tap **Connect Cloudflare**.
2. Tap **Open token creation page** and log in to Cloudflare.
3. If Cloudflare asks for an account, choose your library's. The form is
   already filled in (**Pitak Library Publishing**, **Workers Scripts ·
   Edit**) — change nothing.
4. Tap **Continue to summary**, then **Create Token**.
5. Copy the token now — Cloudflare shows it only once.
6. In Pitak, paste it into **Cloudflare API token** and tap **Connect**.

**Finish in Pitak**

1. In **Choose a Cloudflare account**, tap your account.
2. Asked for the **workers.dev subdomain**? Type it and tap **Continue**.
   Offered **Create workers.dev subdomain** instead? Choose a short name with
   care — every address in your account uses it.
3. In **Choose a Worker**, type a new **Worker name** and tap **Continue**.
4. Asked **Verify the Cloudflare address?** Tap **Deploy verification
   marker**: a tiny test file that proves the address.
5. When the card shows **Confirmed address**, tap **Publish catalogue now**.

**Already publishing on GitHub Pages?**

Connecting Cloudflare does not switch your site: GitHub stays the active
host. To switch, tap **Move to other host** (see **Put your catalogue
online**).

**Good to know**

- Keep the token secret, like a password. Pitak stores it securely on this
  phone. Lost or expired? Make a new one and tap **Reconnect Cloudflare**.
- **Use this Worker for Pitak?** means the name is taken in your account.
  Tap **Replace Worker assets** only if that Worker is for Pitak — everything
  on it is replaced.
- **Disconnect** only forgets the token; your site stays online. To remove
  it, delete the Worker in Cloudflare.

`[ Open Publish to web → ]`

---

### 3.5 Events and posters

> **Added 2026-10-30.** Labels checked against `events_page.dart` (the
> Publish → Events tab) and the public `index.html` events banner.

Card subtitle: *Announce story hours, sales and meetings on your web page*.

**Intro.** Show up to two posters on your public web page — a story hour, a
book sale, a meeting. Your catalogue page then shows a banner at the top that
opens them.

**Put up a poster**

1. Publish your catalogue at least once first (see **Put your catalogue
   online**).
2. Open **☰ → Publish to web → Events**.
3. Tap **Add poster** and pick the poster picture from your gallery.
4. Optional: tap **Add description** and type a line, like "Story hour,
   Saturday 10 AM". Tap **Save**.
5. Tap **Publish events**.

**Change or take down**

- To swap a poster, tap **Remove** on it, add the new one, then tap
  **Publish events** again.
- Removed them all? The button becomes **Clear the events page** — tap it to
  empty the public page.
- Libraries that bookmarked yours see your posters when they open your
  library inside Pitak.

**Good to know**

- **Publish catalogue now** does not send posters, and **Publish events**
  does not send books — use the button for what you changed.
- Posters are public. On GitHub Pages a removed poster stays in the site's
  history, so never put private details on one.
- Posters are not in backups. Keep the original pictures.

`[ Open Events → ]`

---

### 3.6 Put your library on the map

**Intro.** Other Pitak libraries that bookmark yours — by adding your web
address (the link under **Your site** after you publish) to their **Library
Bookmarks** list — see it as a pin on their **Library network › Map**.
Nothing is shown until you switch it on and publish — and you choose how
exact the pin is. *(2026-10-30: the address is no longer called "the GitHub
Pages link" — a Cloudflare library has a `workers.dev` one.)*

**Steps**

1. Find your coordinates: in Google Maps (or OpenStreetMap) press and hold
   on your library's spot. Two numbers appear, like `12.9716, 77.5946` —
   copy them.
2. Open **☰ → Publish to web → Basic info** and tap **Edit**.
3. Paste the numbers into **GPS location**.
4. Under **Share my location on the network map** pick **Approximate
   (~1 km)** or **Exact**. Tap **Save**.
5. Back on **Connection**, tap **Publish catalogue now**. The pin travels
   with your page.
6. Let other libraries save you: send them your site link (**☰ → Share
   Library Website**) or show them your card (**☰ → Library network → My
   card**). When they tap **Refresh**, your pin appears on their map.

**How the map works**

- Your map shows only the libraries on your own **Library network** list —
  the ones you bookmarked, added as members, or that Pitak found through
  your hubs — and only those that publish a location.
- Only web addresses made by Pitak can be bookmarked: they end in
  `github.io`, `pages.dev`, or `<worker>.<name>.workers.dev`. Other websites
  are not accepted. A `workers.dev` library needs a recent Pitak — update the
  app before adding one.
- Pin positions come from each library's published page, read when you tap
  **Refresh**. Nobody's location is sent anywhere else.

**Good to know**

- Pitak never reads your phone's location. It publishes only the numbers
  you type.
- **Approximate** rounds the pin to about 1 km — your neighbourhood, not
  your door.
- To take the pin down, choose **Not shared** and publish again.

`[ Open Basic info → ]`

---

### 3.7 Backup, restore, export, import

**Intro.** All of these live under **☰ → Settings → Data**. Pick by what you
want to do:

| I want to… | Use |
|---|---|
| Keep a complete copy, or move to a new phone | **Create backup** → a `.pitabak` file |
| Bring that copy back | **Restore backup** |
| Share or print my book list | **Export** → JSON, CSV or PDF |
| Add books from a file (a Pitak export, a Goodreads CSV) | **Import** |
| Combine another maintainer's Pitak library with mine | **Merge from a file** |

**Backup — what is inside.** Your whole catalogue — books, magazine titles
and issues, other items — plus wishlist, cover images, library identity and
saved-libraries list, and the borrowers vault if you have one (it stays
encrypted and opens with the same passphrase).
**Not inside:** events and posters, logo, contact details, publishing setup,
app settings — set those up again after a restore.
Keep the file somewhere private (your Drive, a computer) — it is your data in
plain form, except the vault.

**Make a backup**

1. **☰ → Settings → Data → Create backup**.
2. Tap **Create backup** and choose where to save the file.

**Restore on a new phone**

1. Install Pitak → **☰ → Settings → Data → Restore backup**.
2. Tap **Choose .pitabak file** and pick it. Pitak shows what the file
   contains.
3. If it contains a vault, enter that vault's passphrase. Tap **Restore**.

Restoring **replaces** this phone's books, wishlist, covers, identity and
saved libraries with the backup's. It is all-or-nothing: if anything goes
wrong, nothing changes.

**Export vs backup.** Export is for *sharing*: JSON keeps every detail and can
be imported again; CSV opens in a spreadsheet; PDF is a printable catalogue
(you pick the columns). A backup is for *you*: it is the only file that
carries the vault and the covers.

**Import** adds to your library — nothing is deleted. A book that is already
here is updated if it is the same Pitak book, or skipped if it has the same
ISBN.

**Good to know**

- Make a backup before a restore or a merge.
- A backup that contains a vault replaces your current vault when restored.

`[ Open Settings → Data → ]`

---

### 3.8 Lending and the borrowers vault

**Intro.** The vault is Pitak's locked drawer: who borrowed which item, when
it is due, and how to reach them. It is encrypted on this phone and opens
only with your passphrase. Your catalogue is never locked — you can catalogue
without opening the vault.

**Set up once**

1. **☰ → Borrowers vault**.
2. Choose a passphrase of at least 8 characters and type it twice.
   **Write it down somewhere safe** — it is the only key. Pitak never stores
   it and cannot reset it.
3. Optional: **☰ → Settings → Security → Biometric unlock** to open the
   vault with your fingerprint or face from then on.

**Lend an item**

1. Open the item and tap **Lend**. (Locked vault? Unlock it first.)
2. Pick an **Existing borrower**, or type a **New borrower name**.
3. Set a **Due date** if you want a reminder. Tap **Lend**.

**Returns and reminders**

- **☰ → Borrowers vault**, tap the borrower, tap **Edit** → **Return** next
  to the item.
- The bell icon (**Pending**) on the vault screen lists overdue loans, loans
  due soon, and items missing details.
- Add a phone or email on a borrower's page and you get **Call**,
  **WhatsApp** and **Email** buttons there.

**Good to know**

- The vault stays open until you tap the lock icon or close the app — there
  is no timer. Lock it before handing your phone to someone.
- **Require biometric to open Pitak** (Settings → Security) is a different
  thing: it covers the whole app with a prompt but does not encrypt
  anything. The vault is the encrypted part.
- Your published page can show "available / on loan" — never who borrowed.
  It only does so if the vault was unlocked when you published.

`[ Open Borrowers vault → ]`

---

### 3.9 Hubs, members and library cards

**Intro.** **☰ → Library network** is your list of other Pitak libraries.
Nothing leaves your phone until you tap **Refresh**, which reads each
library's published page, or you open a library to browse its published
catalogue inside Pitak.

**What a hub is.** A hub is a Pitak library that lists other libraries as
its members — picture a wheel: the hub in the middle, the members as the
spokes. Any library can be a hub; it only needs a published page, and it can
have no books of its own.

**Two examples**

1. **A library association.** The association sets up Pitak and publishes a
   page. At each meeting it scans a member library's card (**Add member**).
   The association's page lists every member; each member is asked once
   whether to show the membership, and after it says yes and publishes, its
   page points back to the association.
2. **A main library with branches.** Each branch runs its own Pitak with its
   own page. The main library scans each branch's card. Its page lists all
   the branches; each branch's page points back to the main library.

- **☰ → Library Bookmarks → Add Bookmark** saves a library by its web address.
- Tap a saved library to browse its published catalogue inside Pitak —
  search, filter and sort it without leaving the app. Pitak keeps a saved
  copy and downloads it again only when the library changed it; if the
  library can't be reached, you see the saved copy with a note saying how old
  it is. Needing the full website? Use **Open in browser** on that screen.
- **Add member** scans another library's card, in person. That makes you a
  *hub* and lists them on your page as your member.
- If a hub lists *you*, Pitak asks once: "show that you're a member of X?"
  Say yes and it appears on your page; say no and you are not asked again.
- **My card** is your own card to show — it is your site address plus a
  public fingerprint, never your private library ID.

`[ Open Library network → ]`

---

## 4. Decisions (implemented)

1. **Drawer:** use **How Pitak works** in the scrolling destination list;
   **Settings** remains pinned at the bottom.
2. **Index:** nine cards open separate pages, not an accordion; catalogue is
   first and the network guide is included. Related guides sit together:
   wishlist after catalogue; Cloudflare and events right after publish.
3. **Deep links:** every guide has a destination button; **Open Basic info**
   selects Publish's Basic info tab, **Open Events** selects its Events tab,
   and **Open Magazines** opens the magazine-titles page. The publish and
   Cloudflare guides deliberately share **Open Publish to web** — both host
   cards live on that screen.
4. **Coordinates:** keep the Google Maps / OpenStreetMap press-and-hold
   instruction; the optional address sentence was not added.
5. **Repository wording:** keep the real **Set up a repository** label and
   explain "repository" once.
6. **Contextual help:** no `?` guide icons currently ship in Publish or
   Vault; the drawer is the guide entry point.
7. **Cloudflare gets its own guide (2026-10-30):** GitHub needs one sign-in
   code, Cloudflare up to four values fetched from Cloudflare's website.
   Folding "what each value is and where to find it" into the publish guide
   would have pushed it past the 3800 dp copy-length budget in
   `guide_page_test.dart`, so the publish guide keeps a short pointer and the
   new guide holds the detail.
8. **"You need" chips:** only the two hosting guides show one (an account to
   create before starting); every other guide works out of the box.

## 5. Facts behind the copy (verified on appViewer, 2026-10-25)

| Claim | Where it comes from |
|---|---|
| Nine cards in catalogue → wishlist → publish → Cloudflare → events → map → backup → vault → network order; subtitles and destinations | `guide_catalog.dart` (order); `catalog/*.dart` (copy); `guides_page.dart`; `guide_destinations.dart` |
| Cloudflare token page opens pre-filled: name "Pitak Library Publishing", permission Workers Scripts · Edit, one account | `cloudflareTokenCreationUri` in `cloudflare_token_dialog.dart` (pinned by `guide_catalog_test.dart`) |
| Account picker, with a manual **Account ID** path (32 hex characters) when the token cannot list accounts | `CloudflareAccountFlow`; `CloudflareAccountId.length` (pinned by `guide_catalog_test.dart`) |
| Subdomain: read when allowed; **Create workers.dev subdomain** when the account has none; typed (unverified until the marker is read back) when the token cannot read it | `CloudflareSubdomainCommands`; `cloudflare_name_dialogs.dart` |
| Worker names: lower-case letters, numbers, hyphens; no hyphen at either end | `CloudflareWorkerName`; `CloudflareErrorMessages.invalidWorker`; `_LowerCaseTextFormatter` |
| **Use this Worker for Pitak?** / **Replace Worker assets** appears only for an existing Worker; **Deploy verification marker** proves a typed address | `cloudflare_verification_dialog.dart`; `CloudflareConnectionController._runWorkerCommand` |
| Cloudflare becomes the active host only when no host is active; otherwise **Move to other host** switches | `PublishHostStateRepository.ensureActiveHost`; `move_site_controls.dart` |
| Disconnect forgets only the token; the Worker and site stay | `CloudflareErrorMessages.disconnected`; `SetupCloudflareSite.disconnect` |
| Cloudflare dashboard: Account ID under **Workers & Pages → Account details**; subdomain next to **Your subdomain**; token flow **Continue to summary → Create Token** | Cloudflare docs, checked 2026-10-30: "Find account and zone IDs", "workers.dev", "Account API tokens" |
| Up to two posters, optional description (≤ 280 chars); publishing needs a published catalogue; empty list publishes as **Clear the events page** | `EventsContent.maxPosters`; `EventPoster.maxDescriptionLength`; `events_page.dart` |
| Catalogue and events publish separately | `PublishLibraryUseCase` (catalogue section only); `PublishEventsUseCase` |
| The catalogue page shows an events banner when events exist; saved libraries show posters in Pitak | `assets/publish/index.html` (`eventsBanner`); `published_events_section.dart` |
| GitHub keeps removed posters in Git history | `events_page.dart` removal copy |
| Wishlist add form: Title required; ISBN scan fills the ISBN only; lookup is a separate tap and fills empty fields | `add_wishlist_page.dart` (`_scanIsbn`, `_lookupIsbn`) |
| **Purchased — add to library** adds a book unless its ISBN is already there; **Mark as purchased only** adds nothing | `MarkWishlistPurchasedUseCase` (`MarkPurchasedAlreadyInLibrary`); `wishlist_detail_page.dart` |
| The wishlist is never published | no wishlist reference under `lib/features/publish/` |
| Magazines sits between Wishlist and Library network; Settings is pinned | `app_drawer.dart` |
| Tapping a saved library opens its published catalogue in a native, read-only page; the browser is only the explicit **Open in browser** action | `published_catalogue_page.dart` (`PublishedSiteOpener` → `LaunchMode.externalApplication`); `network_page.dart` info note |
| Sign-in is a code + github.com/login/device, works from another device | `github_connection_dialogs.dart` ("Authorize in your browser", tip text) |
| "Set up a repository" creates a public repo and enables Pages itself | `publish_page.dart` target-repo section; `setup_github_repo.dart` |
| Site "can take a minute to update" | `github_connection_controller.dart` success message |
| Only changed files are uploaded | `PublishLibraryUseCase` sha-skip via manifest |
| Availability published only when vault unlocked; borrowers never | `PublishLibraryUseCase.availabilityOmitted`; publish page intro |
| Location switch: Not shared / Approximate (~1 km) / Exact; default off | `basic_info_tab.dart`; `LocationSharing` |
| Phone GPS is never read; coordinates are typed as "lat, lng" | `BuildOwnDescriptor.ownLocation` (D6); GPS field hint |
| Approximate = rounded to 2 decimals ≈ 1.1 km | `GeoPoint.coarsen()` |
| Others see the pin after saving you and tapping Refresh | `RefreshNetworkUseCase`; map page |
| Backup carries the whole catalogue, including magazine titles/issues and item kinds; events/posters, logo, contact details, publishing setup and app settings are excluded | `create_backup_page.dart`; `create_backup_use_case.dart`; `backup_manifest.dart`; `restore_page.dart`; ADR 0014 W2 |
| Restore is all-or-nothing; shows contents first; passphrase only if vault | `restore_page.dart`; `RestoreController` |
| Export formats JSON/CSV/PDF; import adds, updates same-identity, skips same-ISBN | `export_page.dart`, `import_page.dart` |
| Passphrase ≥ 8 chars, never stored, no reset | `VaultSessionController.minPassphraseLength`; vault page copy |
| Biometric unlock is opt-in; app-lock is a screen cover, not encryption | `settings_page.dart` Security section; ADR 0006 |
| No auto-lock | ADR 0006 |
| Lend: existing/new borrower, optional due date; Return on borrower Edit page; Pending = overdue/due soon/missing metadata | `lend_book_page.dart`, `borrower_edit_page.dart`, `pending_page.dart` |
| Call / WhatsApp / Email buttons from phone/email fields | `borrower_profile_page.dart` |
| Card = site URL + public fingerprint, never the ID; Add member is in-person | `network_page.dart` My card tab; ADR 0012 |
| Three kinds, app-defined; one list / search / lendable unit for every kind | `ItemKind` (ADR 0013 F1–F3); `LendDecision.forItem`; FTS over the base table |
| "+" sheet entries: Add book · Add magazine issue · Add other item · New magazine title; "Scan to add" | `add_sheet.dart`; `library_page.dart` app-bar tooltip |
| Issue needs an issue number or a cover date; title is projected ("Title preview") | `add_issue_page.dart` `_validationError`; `IssueTitle.compose` (ADR 0013 D3, D6) |
| Series edit re-projects every issue | `UpdatePeriodicalUseCase` / `IssueReprojection` (D3) |
| Bound volume = one row with a date range; one loan | `AddIssuePage` "Bound volume" switch; ADR 0013 D4 |
| Expiring soon = 30 days before the end date, then Lapsed; only when tracked | `SubscriptionStatus.of` (D5); `SubscriptionBadge` |
| Kind chips Books · Magazines · Others, toggle semantics; search covers notes | `LibraryControlsRow`; `ItemKind.label` (U1); FTS `notes` column (D10) |
| Backups, exports, merges, publish carry kinds | ADR 0014 W1–W3; `.pitabak` `item_kinds.json` / `periodicals.json` |
| Kind cannot change after creation; "Delete permanently" exists on the item page | `UpdateIssueUseCase` (D8); `catalogue_item_actions.dart` |
| A title with issues cannot be deleted | `PeriodicalHasIssuesFailure` (D8); series overflow menu offers Remove / Restore and Delete permanently |
| Other item's Description is private; publish shows title/cover/language/age group | ADR 0013 O2; `PublishItem` redaction |
