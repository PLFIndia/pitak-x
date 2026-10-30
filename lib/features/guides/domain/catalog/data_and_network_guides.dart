/// Data and network guides of "How Pitak works": backup/restore/export/import
/// and the library network. Copy only — the index order and lookup live in
/// `guide_catalog.dart`.
library;

// Why this lint is off for THIS file: every list element is a sentence
// split over several lines with adjacent string literals (the only
// const-friendly way to keep lines ≤ 80 chars — `+` trips
// prefer_adjacent_string_concatenation and parentheses trip
// unnecessary_parenthesis). The lint guards against a missing comma merging
// two items; `guide_catalog_test.dart` pins the exact item count of every
// section, so a lost comma still fails CI.
// ignore_for_file: no_adjacent_strings_in_list

import 'package:pitaka/features/guides/domain/guide.dart';

/// "Backup, restore, export, import": which data tool to use when.
const Guide backupGuide = Guide(
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

/// "Hubs, members and library cards": the library network.
const Guide networkGuide = Guide(
  id: GuideId.network,
  title: 'Hubs, members and library cards',
  cardSubtitle: 'Your list of other Pitak libraries — and what a hub is',
  intro:
      '**☰ → Library network** is your list of other Pitak libraries. Nothing '
      'leaves your phone until you tap **Refresh**, which reads each '
      "library's published page or you open a library to browse its "
      'published catalogue inside Pitak.',
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
        '**☰ → Library Bookmarks → Add Bookmark** saves a library by its web '
            'address.',
        'Tap a saved library to browse its published catalogue inside Pitak '
            '(search, filter and sort it without leaving the app). If you '
            'need the full website, use **Open in browser** on that screen.',
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
