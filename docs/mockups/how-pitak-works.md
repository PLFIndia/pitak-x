# Mockup — "How Pitak works" (information page in the drawer)

> **Status: approved and implemented (2026-10-19).** This file is the design
> and copy record; the copy the app ships is
> `lib/features/guides/domain/guide_catalog.dart` — edit both together.
> Every step below was checked against the current screens and button labels
> (branch `libNetwork`, 2026-10-19). The "Facts behind the copy" section at the
> end lists what each claim rests on, so a wording change in the app can be
> matched here.
>
> Differences between this draft and the shipped catalog (all structural, no
> claim changed): Markdown italics (`*…*`) are plain text — the in-app markup
> has only `**bold**` and `` `code` ``; the "What goes online / Never goes
> online" lines render after the "You need" chips; the fourth and fifth cards
> carry one-line subtitles taken from their intros; the decisions in §4 were
> all taken as proposed (label "How Pitak works", cards → pages, deep-link
> buttons, fifth card included).

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
│ ⬡   Library network          │
│ ↗   Share Library Website    │   (only once published — unchanged)
│ ❔  How Pitak works          │   ← NEW (icon: help_outline)
├──────────────────────────────┤
│ ⚙   Settings                 │
└──────────────────────────────┘
```

Alternative: pin it at the bottom next to Settings. I'd keep it in the list —
Settings is the only "pinned" item today and the drawer comment says so.

## 2. Page layout

**Page: "How Pitak works"** — a short intro line and five cards. Tapping a
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
│ ┌──────────────────────────────────┐ │
│ │ ☁️  Put your catalogue online     │ │
│ │     A free public web page of    │ │
│ │     your books — in 6 steps    ��� │ │
│ └──────────────────────────────────┘ │
│ ┌──────────────────────────────────┐ │
│ │ 📍 Put your library on the map   │ │
│ │     Let nearby libraries find    │ │
│ │     you — you choose how exact › │ │
│ └──────────────────────────────────┘ │
│ ┌──────────────────────────────────┐ │
│ │ 💾 Backup, restore, export,      │ │
│ │     import — which one when    › │ │
│ └──────────────────────────────────┘ │
│ ┌──────────────────────────────────┐ │
│ │ 🔒 Lending and the borrowers     │ │
│ │     vault                      › │ │
│ └──────────────────────────────────┘ │
│ ┌──────────────────────────────────┐ │
│ │ ⬡  Hubs, members and library     │ │
│ │     cards (optional 5th card)  › │ │
│ └──────────────────────────────────┘ │
└──────────────────────────────────────┘
```

**Guide page anatomy** (same skeleton for all five):

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

### 3.1 Put your catalogue online

**Intro.** Pitak can turn your book list into a simple public web page that
anyone can open and search. It is free — the page is hosted by GitHub.

**What goes online:** titles, authors, covers, and — if your vault is
unlocked when you publish — whether a book is available.
**Never goes online:** borrowers, loans, notes, shelf locations.

**You need:** a free GitHub account (github.com — sign-up takes two
minutes) · internet.

**First time**

1. Open **☰ → Publish to web**.
2. Tap **Sign in to GitHub**. Pitak shows a short code.
3. Open the link shown (github.com/login/device) — on this phone or on a
   computer — log in to GitHub and type the code. Come back to Pitak; it
   continues by itself.
4. Tap **Set up a repository**, give it a short name like `my-library`, tap
   **Create**. (A repository is just the folder on GitHub that holds your
   page. Pitak creates it and switches the page on.)
5. Tap **Publish catalogue now**.
6. Your web address appears under **Your site**. Tap **Copy link** or
   **Share**. The first time, the page can take a minute or two to go live.

**Every time after that**

Added or lent books? Open **Publish to web** and tap **Publish catalogue
now** again. Only what changed is uploaded, so it takes seconds.

**Good to know**

- The **Basic info** tab adds your library's name, address, email and phone
  to the page. Every field is optional.
- Signing out of GitHub does not take your page down.
- Sign-in not finishing? Keep the code screen open and type the code in a
  browser on a computer instead.

`[ Open Publish to web → ]`

---

### 3.2 Put your library on the map

**Intro.** Other Pitak libraries that bookmark yours — by adding your web
address (the GitHub Pages link Pitak created) to their **Library network**
list — see it as a pin on their **Library network › Map**. Nothing is shown
until you switch it on and publish — and you choose how exact the pin is.

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
- Only web addresses made by Pitak can be bookmarked (they end in
  `github.io` or `pages.dev`). Other websites are not accepted.
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

### 3.3 Backup, restore, export, import

**Intro.** All of these live under **☰ → Settings → Data**. Pick by what you
want to do:

| I want to… | Use |
|---|---|
| Keep a complete copy, or move to a new phone | **Create backup** → a `.pitabak` file |
| Bring that copy back | **Restore backup** |
| Share or print my book list | **Export** → JSON, CSV or PDF |
| Add books from a file (a Pitak export, a Goodreads CSV) | **Import** |
| Combine another maintainer's Pitak library with mine | **Merge from a file** |

**Backup — what is inside.** Your books, wishlist, cover images, library
identity and saved-libraries list, plus the borrowers vault if you have one
(it stays encrypted and opens with the same passphrase).
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

### 3.4 Lending and the borrowers vault

**Intro.** The vault is Pitak's locked drawer: who borrowed which book, when
it is due, and how to reach them. It is encrypted on this phone and opens
only with your passphrase. Your book list is never locked — you can catalogue
without opening the vault.

**Set up once**

1. **☰ → Borrowers vault**.
2. Choose a passphrase of at least 8 characters and type it twice.
   **Write it down somewhere safe** — it is the only key. Pitak never stores
   it and cannot reset it.
3. Optional: **☰ → Settings → Security → Biometric unlock** to open the
   vault with your fingerprint or face from then on.

**Lend a book**

1. Open the book and tap **Lend**. (Locked vault? Unlock it first.)
2. Pick an **Existing borrower**, or type a **New borrower name**.
3. Set a **Due date** if you want a reminder. Tap **Lend**.

**Returns and reminders**

- **☰ → Borrowers vault**, tap the borrower, tap **Edit** → **Return** next
  to the book.
- The bell icon (**Pending**) on the vault screen lists overdue loans, loans
  due soon, and books missing details.
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

### 3.5 Hubs, members and library cards (optional fifth card)

Worth having because the map guide sends people here. Shortest honest
version:

**Intro.** **☰ → Library network** is your list of other Pitak libraries.
Nothing leaves your phone until you tap **Refresh**, which reads each
library's published page.

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

- **Add bookmark** saves a library by its web address.
- **Add member** scans another library's card, in person. That makes you a
  *hub* and lists them on your page as your member.
- If a hub lists *you*, Pitak asks once: "show that you're a member of X?"
  Say yes and it appears on your page; say no and you are not asked again.
- **My card** is your own card to show — it is your site address plus a
  public fingerprint, never your private library ID.

`[ Open Library network → ]`

---

## 4. Things to decide

1. **Drawer label:** "How Pitak works" vs "Help & guides" vs "Information".
   I'd avoid "Information" — it does not say what you get.
2. **Cards → pages** (proposed) vs an accordion on one page. Pages give each
   guide a deep-link button and keep the first screen scannable.
3. **Deep-link buttons:** worth it? They turn a guide into a "do it now"
   flow and are cheap (the pages already exist). Basic info needs the
   Publish page opened on tab 2.
4. **Include the fifth card** (hubs/members)? The map guide references
   "My card" and "Add member", so without it those words are unexplained.
5. **Coordinates help:** step 1 of the map guide assumes Google Maps'
   press-and-hold. If you prefer, add a one-line "or type your address in
   the Library address field instead — that becomes a map search link on
   your page, not a pin". That is already true today.
6. **Wording check on "repository":** kept once, explained in brackets.
   Alternative is to hide the word completely ("Tap **Set up a
   repository**" is the real button label, so it has to appear at least
   once).
7. Later: should the four guides be reachable from the screens themselves
   (a `?` icon in the Publish and Vault app bars)? Same pages, two doors.

## 5. Facts behind the copy (verified in code, for whoever edits this later)

| Claim | Where it comes from |
|---|---|
| Sign-in is a code + github.com/login/device, works from another device | `github_connection_dialogs.dart` ("Authorize in your browser", tip text) |
| "Set up a repository" creates a public repo and enables Pages itself | `publish_page.dart` target-repo section; `setup_github_repo.dart` |
| Site "can take a minute to update" | `github_connection_controller.dart` success message |
| Only changed files are uploaded | `PublishLibraryUseCase` sha-skip via manifest |
| Availability published only when vault unlocked; borrowers never | `PublishLibraryUseCase.availabilityOmitted`; publish page intro |
| Location switch: Not shared / Approximate (~1 km) / Exact; default off | `basic_info_tab.dart`; `LocationSharing` |
| Phone GPS is never read; coordinates are typed as "lat, lng" | `BuildOwnDescriptor.ownLocation` (D6); GPS field hint |
| Approximate = rounded to 2 decimals ≈ 1.1 km | `GeoPoint.coarsen()` |
| Others see the pin after saving you and tapping Refresh | `RefreshNetworkUseCase`; map page |
| Backup contents / exclusions | `create_backup_page.dart` copy; ARCHITECTURE §5.5 |
| Restore is all-or-nothing; shows contents first; passphrase only if vault | `restore_page.dart`; `RestoreController` |
| Export formats JSON/CSV/PDF; import adds, updates same-identity, skips same-ISBN | `export_page.dart`, `import_page.dart` |
| Passphrase ≥ 8 chars, never stored, no reset | `VaultSessionController.minPassphraseLength`; vault page copy |
| Biometric unlock is opt-in; app-lock is a screen cover, not encryption | `settings_page.dart` Security section; ADR 0006 |
| No auto-lock | ADR 0006 |
| Lend: existing/new borrower, optional due date; Return on borrower Edit page; Pending = overdue/due soon/missing metadata | `lend_book_page.dart`, `borrower_edit_page.dart`, `pending_page.dart` |
| Call / WhatsApp / Email buttons from phone/email fields | `borrower_profile_page.dart` |
| Card = site URL + public fingerprint, never the ID; Add member is in-person | `network_page.dart` My card tab; ADR 0012 |
