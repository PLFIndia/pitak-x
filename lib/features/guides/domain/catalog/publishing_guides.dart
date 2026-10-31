/// Publishing guides of "How Pitak works": the public web page on either
/// host, the Cloudflare setup, event posters and the network-map pin. Copy
/// only — the index order and lookup live in `guide_catalog.dart`.
///
/// Cloudflare's own dashboard labels (**Workers & Pages**, **Account
/// details**, **Your subdomain**, **Continue to summary**, **Create Token**)
/// come from Cloudflare's documentation, not from Pitak; Cloudflare can rename
/// them, so recheck them when its dashboard changes.
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

/// "Put your catalogue online": what goes online, GitHub Pages step by step,
/// and moving between the two hosts.
const Guide publishGuide = Guide(
  id: GuideId.publish,
  title: 'Put your catalogue online',
  cardSubtitle:
      'A free public web page of your books — on GitHub or Cloudflare',
  intro:
      'Pitak can turn your book list into a simple public web page that '
      'anyone can open and search. It is free: on **GitHub Pages**, or on '
      '**Cloudflare Workers** in your own account — one address at a time.',
  needs: [
    'A free GitHub account (github.com), or a free Cloudflare account '
        '(dash.cloudflare.com)',
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
      title: 'First time on GitHub Pages',
      steps: [
        'Open **☰ → Publish to web**.',
        'Tap **Sign in to GitHub**. Pitak shows a short code.',
        'Open the link shown (github.com/login/device) — on this phone or on '
            'a computer — log in to GitHub and type the code. Come back to '
            'Pitak; it continues by itself.',
        'Tap **Set up a repository**, give it a short name like `my-library`, '
            'tap **Create** — that folder is where your page lives.',
        'Tap **Publish catalogue now**.',
        'Your web address appears under **Your site**. Tap **Copy link** or '
            '**Share**. The first time, the page can take a minute or two to '
            'go live.',
      ],
    ),
    GuideParagraphs(
      title: 'Or use Cloudflare Workers',
      paragraphs: [
        'On **Publish to web**, tap **Connect Cloudflare** on the Cloudflare '
            'Workers card. Cloudflare needs a few more details than GitHub: a '
            'token (a password just for Pitak), your account, your '
            '`workers.dev` name and a name for your site. The next guide, '
            '**Set up Cloudflare Workers**, explains each one and where to '
            'find it.',
        '**Give the Worker to Pitak alone:** every publish replaces '
            'everything already on it, so publish from one phone at a time. '
            'Pitak calls the site live only after it reads the published files '
            'back. Moving into a Worker that already holds a test page or '
            'another copy asks first, and the button says **Replace and '
            'move**.',
      ],
    ),
    GuideParagraphs(
      title: 'Every time after that',
      paragraphs: [
        'Added or lent books? Open **Publish to web** and tap **Publish '
            'catalogue now** again. Only what changed is uploaded, so it takes '
            'seconds. It publishes to whichever host is active. When Pitak '
            'only checks an earlier publish, the message says **Verified** — '
            'nothing new was published.',
      ],
    ),
    GuideParagraphs(
      title: 'Moving to the other host later',
      paragraphs: [
        'You can move the page between the two hosts. Pitak verifies the new '
            'site first, then turns the old address into a short "moved" page. '
            'If that last step cannot finish, the publish page keeps three '
            'choices: Retry move, Skip retirement (only when the old site is '
            'really gone) and Cancel move (which keeps your current site and '
            'leaves the new copy online until you delete it; it is offered '
            'only until the old address shows the moved page). If Pitak cannot '
            'sign in to the old site at all, Finish without retiring replaces '
            'Skip behind a stronger warning — that copy also stays online. '
            'Other phones never follow a move by themselves — they may offer '
            'the choice to their owner — and a printed library card still '
            'shows the old address, so reprint it after a move.',
      ],
    ),
  ],
  goodToKnow: [
    "The **Basic info** tab adds your library's name, address, email and "
        'phone to the page. Every field is optional.',
    'Signing out of GitHub does not take your page down. Disconnecting '
        'Cloudflare only forgets the token — it never deletes the Worker.',
    'Sign-in not finishing? Keep the code screen open and type the code in a '
        'browser on a computer instead.',
  ],
  destination: GuideDestination.publishConnection,
  destinationLabel: 'Open Publish to web',
);

/// "Set up Cloudflare Workers": every value the Cloudflare setup asks for,
/// where to find it, and the setup steps.
///
/// Why this guide exists on its own (2026-10-30): GitHub asks for one sign-in
/// code, but Cloudflare asks for up to four values the reader has to fetch
/// from Cloudflare's website. The publish guide could only name them; this
/// guide says what each value is and where to find it, in the order Pitak
/// asks.
///
/// Facts behind the copy: the token link and its pre-filled name/permission
/// are `cloudflareTokenCreationUri` (cloudflare_token_dialog.dart); the
/// account picker, the manual Account ID path and the subdomain prompts are
/// `CloudflareAccountFlow` / `CloudflareSubdomainCommands` (a Workers Scripts
/// only token usually cannot read the subdomain, so the typed path is the
/// common one); Cloudflare becomes the active host only when no host is
/// active yet (`ensureActiveHost`). `guide_catalog_test.dart` pins the
/// pre-filled token name and the Account ID length to that code.
const Guide cloudflareGuide = Guide(
  id: GuideId.cloudflare,
  title: 'Set up Cloudflare Workers',
  cardSubtitle: 'The other free host — what to type and where to find it',
  intro:
      'Cloudflare can hold your public catalogue for free, instead of GitHub '
      'Pages. Your site lives in a "Worker": one small website in your '
      'Cloudflare account. Setting it up takes about ten minutes, once.',
  needs: ['A free Cloudflare account (dash.cloudflare.com)'],
  sections: [
    GuideBullets(
      title: 'What Pitak will ask you for',
      bullets: [
        '**Cloudflare API token** — a secret code, like a password just for '
            'Pitak. It can only update your website. You create it on '
            "Cloudflare's website (steps below).",
        '**Your account** — Pitak lists it; tap it. Asked for an **Account '
            'ID** instead? In Cloudflare open **Workers & Pages** and copy it '
            'from **Account details** (32 letters and numbers).',
        "**workers.dev subdomain** — your account's part of the address: "
            '`asha-books` in `asha-books.workers.dev`. If Pitak asks for it, '
            'find it in Cloudflare under **Workers & Pages**, next to **Your '
            'subdomain**; type only the part before `.workers.dev`.',
        '**Worker name** — a name you make up for your site, like `library`, '
            'giving `library.asha-books.workers.dev`. Use lower-case letters, '
            'numbers and hyphens (-), no hyphen at either end.',
      ],
    ),
    GuideSteps(
      title: 'Create the token (in your browser)',
      steps: [
        'Open **☰ → Publish to web** and tap **Connect Cloudflare**.',
        'Tap **Open token creation page** and log in to Cloudflare.',
        "If Cloudflare asks for an account, choose your library's. The form "
            'is already filled in (**Pitak Library Publishing**, **Workers '
            'Scripts · Edit**) — change nothing.',
        'Tap **Continue to summary**, then **Create Token**.',
        'Copy the token now — Cloudflare shows it only once.',
        'In Pitak, paste it into **Cloudflare API token** and tap '
            '**Connect**.',
      ],
    ),
    GuideSteps(
      title: 'Finish in Pitak',
      steps: [
        'In **Choose a Cloudflare account**, tap your account.',
        'Asked for the **workers.dev subdomain**? Type it and tap '
            '**Continue**. Offered **Create workers.dev subdomain** instead? '
            'Choose a short name with care — every address in your account '
            'uses it.',
        'In **Choose a Worker**, type a new **Worker name** and tap '
            '**Continue**.',
        'Asked **Verify the Cloudflare address?** Tap **Deploy verification '
            'marker**: a tiny test file that proves the address.',
        'When the card shows **Confirmed address**, tap **Publish catalogue '
            'now**.',
      ],
    ),
    GuideParagraphs(
      title: 'Already publishing on GitHub Pages?',
      paragraphs: [
        'Connecting Cloudflare does not switch your site: GitHub stays the '
            'active host. To switch, tap **Move to other host** (see **Put '
            'your catalogue online**).',
      ],
    ),
  ],
  goodToKnow: [
    'Keep the token secret, like a password. Pitak stores it securely on this '
        'phone. Lost or expired? Make a new one and tap **Reconnect '
        'Cloudflare**.',
    '**Use this Worker for Pitak?** means the name is taken in your account. '
        'Tap **Replace Worker assets** only if that Worker is for Pitak — '
        'everything on it is replaced.',
    '**Disconnect** only forgets the token; your site stays online. To remove '
        'it, delete the Worker in Cloudflare.',
  ],
  destination: GuideDestination.publishConnection,
  destinationLabel: 'Open Publish to web',
);

/// "Events and posters": the Publish → Events tab.
const Guide eventsGuide = Guide(
  id: GuideId.events,
  title: 'Events and posters',
  cardSubtitle: 'Announce story hours, sales and meetings on your web page',
  intro:
      'Show up to two posters on your public web page — a story hour, a book '
      'sale, a meeting. Your catalogue page then shows a banner at the top '
      'that opens them.',
  needs: [],
  sections: [
    GuideSteps(
      title: 'Put up a poster',
      steps: [
        'Publish your catalogue at least once first (see **Put your catalogue '
            'online**).',
        'Open **☰ → Publish to web → Events**.',
        'Tap **Add poster** and pick the poster picture from your gallery.',
        'Optional: tap **Add description** and type a line, like "Story hour, '
            'Saturday 10 AM". Tap **Save**.',
        'Tap **Publish events**.',
      ],
    ),
    GuideBullets(
      title: 'Change or take down',
      bullets: [
        'To swap a poster, tap **Remove** on it, add the new one, then tap '
            '**Publish events** again.',
        'Removed them all? The button becomes **Clear the events page** — tap '
            'it to empty the public page.',
        'Libraries that bookmarked yours see your posters when they open your '
            'library inside Pitak.',
      ],
    ),
  ],
  goodToKnow: [
    '**Publish catalogue now** does not send posters, and **Publish events** '
        'does not send books — use the button for what you changed.',
    'Posters are public. On GitHub Pages a removed poster stays in the '
        "site's history, so never put private details on one.",
    'Posters are not in backups. Keep the original pictures.',
  ],
  destination: GuideDestination.publishEvents,
  destinationLabel: 'Open Events',
);

/// "Put your library on the map": location sharing on the network map.
const Guide mapGuide = Guide(
  id: GuideId.map,
  title: 'Put your library on the map',
  cardSubtitle: 'Let nearby libraries find you — you choose how exact',
  intro:
      'Other Pitak libraries that bookmark yours — by adding your web address '
      '(the link under **Your site** after you publish) to their **Library '
      'Bookmarks** list — see it as a pin on their **Library network › Map**. '
      'Nothing is shown until you switch it on and publish — and you choose '
      'how exact the pin is.',
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
        'Only web addresses made by Pitak can be bookmarked: they end in '
            '`github.io`, `pages.dev`, or `<worker>.<name>.workers.dev`. Other '
            'websites are not accepted. A `workers.dev` library needs a '
            'recent Pitak — update the app before adding one.',
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
