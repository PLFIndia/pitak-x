/// The six "How Pitak works" guides — THE source of truth for their copy.
///
/// Text is transcribed verbatim from the approved draft in
/// `docs/mockups/how-pitak-works.md` §3 (2026-10-19; the catalogue guide
/// §3.6 was added with the item-kinds work, 2026-10-23); every bold button /
/// menu label there was checked against the real screens. If a screen's
/// label changes, change it here in the same commit — the catalog test cannot
/// know a button was renamed, only that the markup still parses.
///
/// Terminology: the app's own words (member, hub, magazine title, issue,
/// other item). "Spokes" appears exactly once, as the wheel picture in the
/// hubs guide — `guide_catalog_test.dart` enforces that.
library;

// Why this lint is off for THIS file only: every list element below is a
// sentence split over several lines with adjacent string literals (the only
// const-friendly way to keep lines ≤ 80 chars — `+` trips
// prefer_adjacent_string_concatenation and parentheses trip
// unnecessary_parenthesis). The lint guards against a missing comma merging
// two items; here `guide_catalog_test.dart` pins the exact item count of
// every section, so a lost comma still fails CI.
// ignore_for_file: no_adjacent_strings_in_list

import 'package:pitaka/features/guides/domain/guide.dart';

/// All guides, in the approved index order. The catalogue guide comes first:
/// adding items is the first job anyone does with the app, and the other
/// guides build on a catalogue that already exists.
const List<Guide> guideCatalog = [
  _catalogue,
  _publish,
  _map,
  _backup,
  _vault,
  _network,
];

/// Looks a guide up by [id]. Every [GuideId] has exactly one guide.
Guide guideById(GuideId id) => guideCatalog.firstWhere((g) => g.id == id);

const Guide _catalogue = Guide(
  id: GuideId.catalogue,
  title: 'Books, magazines and other items',
  cardSubtitle: 'Three kinds of item, one library — which form to use',
  intro:
      'Your library holds three kinds of item: **books**, **magazine '
      'issues** (grouped under their magazine title) and **other items** — '
      'a DVD, a board game, a map. One list, one search, one way of '
      'lending; the kind only decides which form you fill in.',
  needs: [],
  sections: [
    GuideTable(
      title: '',
      rows: [
        (
          want: 'Add a book',
          use: '**+** → **Add book**, or **Scan to add** its barcode',
        ),
        (
          want: 'Add a magazine',
          use:
              '**+** → **New magazine title** once, then **Add magazine '
              'issue** per issue',
        ),
        (
          want: 'Add something else',
          use: '**+** → **Add other item**; describe it in **Description**',
        ),
      ],
    ),
    GuideSteps(
      title: 'Catalogue a magazine',
      steps: [
        'On the Library screen tap **+**, then **New magazine title**.',
        'Type the title (ISSN, publisher and frequency are optional) and tap '
            '**Add magazine title**.',
        'Open **☰ → Magazines**, tap the magazine, then **Add issue**.',
        'Type the **Issue number** or pick a **Cover date**; **Title '
            'preview** shows the name the issue will get.',
        'Tap **Add issue**. The issue is listed under its magazine and in '
            'the Library.',
      ],
    ),
    GuideBullets(
      title: 'How magazines behave',
      bullets: [
        'An issue takes its title, publisher and language from its magazine '
            'title; edit the title once and every issue follows.',
        '**Bound volume** (a switch on the issue form): several issues bound '
            'as one physical item, identified by its first and last issue '
            'dates. One item, one loan.',
        '**Track subscription** on a magazine title makes the **Magazines** '
            'list warn **Expiring soon** 30 days before the end date, then '
            '**Lapsed**.',
      ],
    ),
    GuideBullets(
      title: 'The same for every kind',
      bullets: [
        'Lend any item — a book, an issue, a board game — with **Lend** on '
            'its page.',
        'The chips **Books**, **Magazines**, **Others** show one kind; tap '
            'again for everything. Search reads notes too, so a '
            '**Description** is searchable.',
        'Backups, exports, merges and your published page carry every kind.',
      ],
    ),
  ],
  goodToKnow: [
    'An item keeps its kind — a book cannot later become a magazine issue. '
        '**Delete permanently**, then add it again with the right form.',
    'A magazine title cannot be deleted while it still has issues; delete '
        'those first.',
    "An other item's **Description** stays on this phone; the published "
        'page shows only its title, cover, language and age group.',
  ],
  destination: GuideDestination.magazines,
  destinationLabel: 'Open Magazines',
);

const Guide _publish = Guide(
  id: GuideId.publish,
  title: 'Put your catalogue online',
  cardSubtitle: 'A free public web page of your books — in 6 steps',
  intro:
      'Pitak can turn your book list into a simple public web page that '
      'anyone can open and search. It is free — the page is hosted by GitHub.',
  needs: [
    'A free GitHub account (github.com — sign-up takes two minutes)',
    'Internet',
  ],
  sections: [
    GuideParagraphs(
      title: '',
      paragraphs: [
        '**What goes online:** titles, authors, covers, and — if your vault '
            'is unlocked when you publish — whether a book is available.',
        '**Never goes online:** borrowers, loans, notes, shelf locations.',
      ],
    ),
    GuideSteps(
      title: 'First time',
      steps: [
        'Open **☰ → Publish to web**.',
        'Tap **Sign in to GitHub**. Pitak shows a short code.',
        'Open the link shown (github.com/login/device) — on this phone or on '
            'a computer — log in to GitHub and type the code. Come back to '
            'Pitak; it continues by itself.',
        'Tap **Set up a repository**, give it a short name like `my-library`, '
            'tap **Create**. (A repository is just the folder on GitHub that '
            'holds your page. Pitak creates it and switches the page on.)',
        'Tap **Publish catalogue now**.',
        'Your web address appears under **Your site**. Tap **Copy link** or '
            '**Share**. The first time, the page can take a minute or two to '
            'go live.',
      ],
    ),
    GuideParagraphs(
      title: 'Every time after that',
      paragraphs: [
        'Added or lent books? Open **Publish to web** and tap **Publish '
            'catalogue now** again. Only what changed is uploaded, so it takes '
            'seconds.',
      ],
    ),
  ],
  goodToKnow: [
    "The **Basic info** tab adds your library's name, address, email and "
        'phone to the page. Every field is optional.',
    'Signing out of GitHub does not take your page down.',
    'Sign-in not finishing? Keep the code screen open and type the code in a '
        'browser on a computer instead.',
  ],
  destination: GuideDestination.publishConnection,
  destinationLabel: 'Open Publish to web',
);

const Guide _map = Guide(
  id: GuideId.map,
  title: 'Put your library on the map',
  cardSubtitle: 'Let nearby libraries find you — you choose how exact',
  intro:
      'Other Pitak libraries that bookmark yours — by adding your web address '
      '(the GitHub Pages link Pitak created) to their **Library network** '
      'list — see it as a pin on their **Library network › Map**. Nothing is '
      'shown until you switch it on and publish — and you choose how exact '
      'the pin is.',
  needs: [],
  sections: [
    GuideSteps(
      title: 'Steps',
      steps: [
        'Find your coordinates: in Google Maps (or OpenStreetMap) press and '
            "hold on your library's spot. Two numbers appear, like "
            '`12.9716, 77.5946` — copy them.',
        'Open **☰ → Publish to web → Basic info** and tap **Edit**.',
        'Paste the numbers into **GPS location**.',
        'Under **Share my location on the network map** pick **Approximate '
            '(~1 km)** or **Exact**. Tap **Save**.',
        'Back on **Connection**, tap **Publish catalogue now**. The pin '
            'travels with your page.',
        'Let other libraries save you: send them your site link (**☰ → Share '
            'Library Website**) or show them your card (**☰ → Library network '
            '→ My card**). When they tap **Refresh**, your pin appears on '
            'their map.',
      ],
    ),
    GuideBullets(
      title: 'How the map works',
      bullets: [
        'Your map shows only the libraries on your own **Library network** '
            'list — the ones you bookmarked, added as members, or that Pitak '
            'found through your hubs — and only those that publish a location.',
        'Only web addresses made by Pitak can be bookmarked (they end in '
            '`github.io` or `pages.dev`). Other websites are not accepted.',
        "Pin positions come from each library's published page, read when "
            "you tap **Refresh**. Nobody's location is sent anywhere else.",
      ],
    ),
  ],
  goodToKnow: [
    "Pitak never reads your phone's location. It publishes only the numbers "
        'you type.',
    '**Approximate** rounds the pin to about 1 km — your neighbourhood, not '
        'your door.',
    'To take the pin down, choose **Not shared** and publish again.',
  ],
  destination: GuideDestination.publishBasicInfo,
  destinationLabel: 'Open Basic info',
);

const Guide _backup = Guide(
  id: GuideId.backup,
  title: 'Backup, restore, export, import',
  cardSubtitle: 'Which one when',
  intro:
      'All of these live under **☰ → Settings → Data**. Pick by what you want '
      'to do:',
  needs: [],
  sections: [
    GuideTable(
      title: '',
      rows: [
        (
          want: 'Keep a complete copy, or move to a new phone',
          use: '**Create backup** → a `.pitabak` file',
        ),
        (want: 'Bring that copy back', use: '**Restore backup**'),
        (
          want: 'Share or print my book list',
          use: '**Export** → JSON, CSV or PDF',
        ),
        (
          want: 'Add books from a file (a Pitak export, a Goodreads CSV)',
          use: '**Import**',
        ),
        (
          want: "Combine another maintainer's Pitak library with mine",
          use: '**Merge from a file**',
        ),
      ],
    ),
    GuideParagraphs(
      title: 'Backup — what is inside',
      paragraphs: [
        'Your whole catalogue — books, magazine titles and issues, other '
            'items — plus wishlist, cover images, library identity and '
            'saved-libraries list, and the borrowers vault if you have one '
            '(it stays encrypted and opens with the same passphrase).',
        '**Not inside:** events and posters, logo, contact details, '
            'publishing setup, app settings — set those up again after a '
            'restore.',
        'Keep the file somewhere private (your Drive, a computer) — it is '
            'your data in plain form, except the vault.',
      ],
    ),
    GuideSteps(
      title: 'Make a backup',
      steps: [
        '**☰ → Settings → Data → Create backup**.',
        'Tap **Create backup** and choose where to save the file.',
      ],
    ),
    GuideSteps(
      title: 'Restore on a new phone',
      steps: [
        'Install Pitak → **☰ → Settings → Data → Restore backup**.',
        'Tap **Choose .pitabak file** and pick it. Pitak shows what the file '
            'contains.',
        "If it contains a vault, enter that vault's passphrase. Tap "
            '**Restore**.',
      ],
    ),
    GuideParagraphs(
      title: '',
      paragraphs: [
        "Restoring **replaces** this phone's books, wishlist, covers, "
            "identity and saved libraries with the backup's. It is "
            'all-or-nothing: if anything goes wrong, nothing changes.',
      ],
    ),
    GuideParagraphs(
      title: 'Export vs backup',
      paragraphs: [
        'Export is for sharing: JSON keeps every detail and can be imported '
            'again; CSV opens in a spreadsheet; PDF is a printable catalogue '
            '(you pick the columns). A backup is for you: it is the only file '
            'that carries the vault and the covers.',
      ],
    ),
    GuideParagraphs(
      title: 'Import',
      paragraphs: [
        'Import adds to your library — nothing is deleted. A book that is '
            'already here is updated if it is the same Pitak book, or skipped '
            'if it has the same ISBN.',
      ],
    ),
  ],
  goodToKnow: [
    'Make a backup before a restore or a merge.',
    'A backup that contains a vault replaces your current vault when '
        'restored.',
  ],
  destination: GuideDestination.settingsData,
  destinationLabel: 'Open Settings → Data',
);

const Guide _vault = Guide(
  id: GuideId.vault,
  title: 'Lending and the borrowers vault',
  cardSubtitle:
      'Who borrowed which item, when it is due — encrypted on this phone',
  intro:
      "The vault is Pitak's locked drawer: who borrowed which item, when it "
      'is due, and how to reach them. It is encrypted on this phone and '
      'opens only with your passphrase. Your catalogue is never locked — you '
      'can catalogue without opening the vault.',
  needs: [],
  sections: [
    GuideSteps(
      title: 'Set up once',
      steps: [
        '**☰ → Borrowers vault**.',
        'Choose a passphrase of at least 8 characters and type it twice. '
            '**Write it down somewhere safe** — it is the only key. Pitak '
            'never stores it and cannot reset it.',
        'Optional: **☰ → Settings → Security → Biometric unlock** to open '
            'the vault with your fingerprint or face from then on.',
      ],
    ),
    GuideSteps(
      title: 'Lend an item',
      steps: [
        'Open the item and tap **Lend**. (Locked vault? Unlock it first.)',
        'Pick an **Existing borrower**, or type a **New borrower name**.',
        'Set a **Due date** if you want a reminder. Tap **Lend**.',
      ],
    ),
    GuideBullets(
      title: 'Returns and reminders',
      bullets: [
        '**☰ → Borrowers vault**, tap the borrower, tap **Edit** → **Return** '
            'next to the item.',
        'The bell icon (**Pending**) on the vault screen lists overdue loans, '
            'loans due soon, and items missing details.',
        "Add a phone or email on a borrower's page and you get **Call**, "
            '**WhatsApp** and **Email** buttons there.',
      ],
    ),
  ],
  goodToKnow: [
    'The vault stays open until you tap the lock icon or close the app — '
        'there is no timer. Lock it before handing your phone to someone.',
    '**Require biometric to open Pitak** (Settings → Security) is a '
        'different thing: it covers the whole app with a prompt but does not '
        'encrypt anything. The vault is the encrypted part.',
    'Your published page can show "available / on loan" — never who '
        'borrowed. It only does so if the vault was unlocked when you '
        'published.',
  ],
  destination: GuideDestination.vault,
  destinationLabel: 'Open Borrowers vault',
);

const Guide _network = Guide(
  id: GuideId.network,
  title: 'Hubs, members and library cards',
  cardSubtitle: 'Your list of other Pitak libraries — and what a hub is',
  intro:
      '**☰ → Library network** is your list of other Pitak libraries. Nothing '
      'leaves your phone until you tap **Refresh**, which reads each '
      "library's published page.",
  needs: [],
  sections: [
    GuideParagraphs(
      title: 'What a hub is',
      paragraphs: [
        'A hub is a Pitak library that lists other libraries as its members — '
            'picture a wheel: the hub in the middle, the members as the '
            'spokes. Any library can be a hub; it only needs a published '
            'page, and it can have no books of its own.',
      ],
    ),
    GuideSteps(
      title: 'Two examples',
      steps: [
        '**A library association.** The association sets up Pitak and '
            "publishes a page. At each meeting it scans a member library's "
            "card (**Add member**). The association's page lists every "
            'member; each member is asked once whether to show the '
            'membership, and after it says yes and publishes, its page points '
            'back to the association.',
        '**A main library with branches.** Each branch runs its own Pitak '
            "with its own page. The main library scans each branch's card. "
            "Its page lists all the branches; each branch's page points back "
            'to the main library.',
      ],
    ),
    GuideBullets(
      title: '',
      bullets: [
        '**Add bookmark** saves a library by its web address.',
        "**Add member** scans another library's card, in person. That makes "
            'you a hub and lists them on your page as your member.',
        'If a hub lists you, Pitak asks once: "show that you\'re a member of '
            'X?" Say yes and it appears on your page; say no and you are not '
            'asked again.',
        '**My card** is your own card to show — it is your site address plus '
            'a public fingerprint, never your private library ID.',
      ],
    ),
  ],
  goodToKnow: [],
  destination: GuideDestination.network,
  destinationLabel: 'Open Library network',
);
