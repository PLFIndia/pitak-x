/// The nine "How Pitak works" guides — THE source of truth for their copy.
///
/// Text is transcribed verbatim from the approved draft in
/// `docs/mockups/how-pitak-works.md` §3 (2026-10-19; the catalogue guide
/// was added with the item-kinds work, 2026-10-23; the wishlist, Cloudflare
/// and events guides on 2026-10-30); every bold button / menu label there was
/// checked against the real screens. If a screen's label changes, change the
/// guide in the same commit — the catalog test cannot know a button was
/// renamed, only that the markup still parses.
///
/// Where the copy lives: this file holds the index ORDER and the lookup; the
/// guides themselves are grouped by topic under `catalog/` (library work,
/// publishing, data and network). Why split (beginner note): copy grows, and
/// the file-size ratchet (`layer_boundaries_test.dart`, 500 lines) asks for a
/// split rather than one ever-longer file. The split changes nothing at run
/// time — every guide is still a compile-time constant.
///
/// Terminology: the app's own words (member, hub, magazine title, issue,
/// other item). "Spokes" appears exactly once, as the wheel picture in the
/// hubs guide — `guide_catalog_test.dart` enforces that.
library;

import 'package:pitaka/features/guides/domain/catalog/data_and_network_guides.dart';
import 'package:pitaka/features/guides/domain/catalog/library_guides.dart';
import 'package:pitaka/features/guides/domain/catalog/publishing_guides.dart';
import 'package:pitaka/features/guides/domain/guide.dart';

/// All guides, in the approved index order. The catalogue guide comes first:
/// adding items is the first job anyone does with the app, and the other
/// guides build on a catalogue that already exists. Related guides sit next
/// to each other: the wishlist after the catalogue it feeds, and the
/// Cloudflare and events guides right after the publish guide they extend.
const List<Guide> guideCatalog = [
  catalogueGuide,
  wishlistGuide,
  publishGuide,
  cloudflareGuide,
  eventsGuide,
  mapGuide,
  backupGuide,
  vaultGuide,
  networkGuide,
];

/// Looks a guide up by [id]. Every [GuideId] has exactly one guide.
Guide guideById(GuideId id) => guideCatalog.firstWhere((g) => g.id == id);
