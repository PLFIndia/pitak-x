/// Library-work guides of "How Pitak works": the catalogue, the wishlist
/// and lending. Copy only — the index order and lookup live in
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

/// "Books, magazines and other items": the three item kinds and which
/// form adds each.
const Guide catalogueGuide = Guide(
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

/// "Wishlist: books to buy": noting wanted books and moving one into the
/// library when it arrives.
const Guide wishlistGuide = Guide(
  id: GuideId.wishlist,
  title: 'Wishlist: books to buy',
  cardSubtitle: 'Note the books you want; add one to the library when it comes',
  intro:
      'The wishlist is your shopping list: books you want for the library but '
      'do not have yet. It is kept apart from your catalogue, and it never '
      'appears on your web page.',
  needs: [],
  sections: [
    GuideSteps(
      title: 'Add a book you want',
      steps: [
        'Open **☰ → Wishlist** and tap **+**.',
        'Type the **Title**. Know the ISBN, or have the book in hand? Type the '
            '**ISBN** or tap the barcode button (**Scan barcode**), then tap '
            'the magnifier (**Look up details**) to fill in the rest.',
        'Optional: choose a **Priority** (Low, Medium or High) and add a '
            '**Price estimate** or **Notes**.',
        'Tap **Add**.',
      ],
    ),
    GuideSteps(
      title: 'When the book arrives',
      steps: [
        'Open **☰ → Wishlist** and tap the book.',
        'Tap **Purchased — add to library**. Pitak adds it to your catalogue '
            'and moves it to the **Purchased** list at the bottom of the '
            'wishlist.',
      ],
    ),
  ],
  goodToKnow: [
    '**Mark as purchased only** records that you bought it but adds nothing '
        'to your catalogue.',
    'A book whose ISBN is already in your library is not added twice — Pitak '
        'only marks the wish as purchased.',
    'Scanning only reads the barcode. Pitak goes online only when you tap '
        '**Look up details**.',
  ],
  destination: GuideDestination.wishlist,
  destinationLabel: 'Open Wishlist',
);

/// "Lending and the borrowers vault": lending, returns and the encrypted
/// borrower records.
const Guide vaultGuide = Guide(
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
