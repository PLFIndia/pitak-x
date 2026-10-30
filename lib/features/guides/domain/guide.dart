/// Content model for the in-app "How Pitak works" guides (domain, pure Dart).
///
/// Why the copy lives in `domain/`: the architecture tests
/// (`test/architecture/domain_purity_test.dart`) force this layer to stay
/// free of Flutter, which is exactly what we want for help text — the copy
/// and its invariants (step counts, every guide has a destination, no
/// unparsed markup) are unit-testable without pumping a widget. Anything
/// that IS Flutter (icons, pages) is mapped in presentation from [GuideId]
/// and [GuideDestination]; it is never stored here.
///
/// Every type in this file is immutable. The concrete guides are built once,
/// in `guide_catalog.dart`.
library;

/// Which guide. Presentation maps this to an icon; tests address guides by it.
enum GuideId {
  /// "Books, magazines and other items" (the catalogue's item kinds,
  /// ADR 0013).
  catalogue,

  /// "Wishlist: books to buy" (the wishlist and its move into the library).
  wishlist,

  /// "Put your catalogue online" (both hosts; how publishing works).
  publish,

  /// "Set up Cloudflare Workers" (what the Cloudflare setup asks for and
  /// where the reader finds each value).
  cloudflare,

  /// "Events and posters" (the Publish → Events tab).
  events,

  /// "Put your library on the map" (location sharing on the network map).
  map,

  /// "Backup, restore, export, import".
  backup,

  /// "Lending and the borrowers vault".
  vault,

  /// "Hubs, members and library cards".
  network,
}

/// Where a guide's bottom button goes. Presentation maps each value to a
/// page, so this enum is the only coupling between the copy and navigation.
enum GuideDestination {
  /// The Magazines screen (magazine titles and their issues, ADR 0013 U2).
  magazines,

  /// The Wishlist screen.
  wishlist,

  /// Publish hub, Connection tab (its default tab). Shared by the publish
  /// and Cloudflare guides: both end on the screen that holds the host cards.
  publishConnection,

  /// Publish hub opened on the Basic info tab.
  publishBasicInfo,

  /// Publish hub opened on the Events tab.
  publishEvents,

  /// Settings opened on the Data tab.
  settingsData,

  /// The borrowers vault.
  vault,

  /// The library network.
  network,
}

/// One inline run of guide text, produced by `parseGuideMarkup`.
///
/// A run is either plain, **bold** (`bold: true` — a button / menu label the
/// reader should look for on screen) or `code` (`code: true` — a literal
/// value to type or recognise). The parser never sets both: the markup has
/// no nesting.
///
/// A record rather than a class on purpose: records compare by value, which
/// the parser tests need, without the `@immutable` annotation (`package:meta`)
/// that the domain purity allow-list does not admit (same reasoning as
/// `LibraryQuery.sameIntentAs`).
typedef GuideRun = ({String text, bool bold, bool code});

/// A block inside a guide. Sealed so the renderer's `switch` is exhaustive:
/// adding a new kind here fails to compile until the UI draws it.
sealed class GuideSection {
  /// Creates a section headed by [title].
  const GuideSection({required this.title});

  /// Section heading shown above the block. An empty string means "no
  /// heading": the approved copy has a few lead-in blocks (the "What goes
  /// online" lines, the picker table) that follow the intro directly.
  final String title;

  /// Whether the renderer should draw a heading for this block.
  bool get hasTitle => title.isNotEmpty;
}

/// Numbered steps, one action per step.
final class GuideSteps extends GuideSection {
  /// Creates a numbered-steps section.
  const GuideSteps({required super.title, required this.steps});

  /// The steps in order. The catalog test enforces 2–7 per section.
  final List<String> steps;
}

/// Plain bullet points.
final class GuideBullets extends GuideSection {
  /// Creates a bullet section.
  const GuideBullets({required super.title, required this.bullets});

  /// The bullets in order.
  final List<String> bullets;
}

/// Free-flowing paragraphs.
final class GuideParagraphs extends GuideSection {
  /// Creates a paragraph section.
  const GuideParagraphs({required super.title, required this.paragraphs});

  /// The paragraphs in order.
  final List<String> paragraphs;
}

/// One row of a [GuideTable]: what the reader wants to do, and what to use.
typedef GuideTableRow = ({String want, String use});

/// A two-column "I want to… / Use" picker table.
final class GuideTable extends GuideSection {
  /// Creates a picker table.
  const GuideTable({required super.title, required this.rows});

  /// Header of the first column (what the reader wants to do).
  static const String wantHeader = 'I want to…';

  /// Header of the second column (which screen / button to use).
  static const String useHeader = 'Use';

  /// The rows in order.
  final List<GuideTableRow> rows;
}

/// One guide. Immutable; constructed only in `guide_catalog.dart`.
final class Guide {
  /// Creates a guide.
  ///
  /// [goodToKnow] is capped at [maxGoodToKnow] bullets by design (the copy
  /// rules in `docs/mockups/how-pitak-works.md`): more than three stops being
  /// "only things that avoid a mistake". A const constructor cannot read
  /// `goodToKnow.length` in an `assert`, so `guide_catalog_test.dart` is the
  /// enforcement point.
  const Guide({
    required this.id,
    required this.title,
    required this.cardSubtitle,
    required this.intro,
    required this.needs,
    required this.sections,
    required this.goodToKnow,
    required this.destination,
    required this.destinationLabel,
  });

  /// Upper bound on [goodToKnow] bullets (enforced by the catalog test).
  static const int maxGoodToKnow = 3;

  /// Stable identity (icon lookup, tests).
  final GuideId id;

  /// App-bar title and index-card title.
  final String title;

  /// One line under the card title on the index page.
  final String cardSubtitle;

  /// First paragraph of the guide (markup allowed).
  final String intro;

  /// "You need" chips. May be empty, in which case the row is not shown.
  final List<String> needs;

  /// The guide body, in reading order.
  final List<GuideSection> sections;

  /// "Good to know" callout bullets (≤ [maxGoodToKnow]). May be empty.
  final List<String> goodToKnow;

  /// Where the bottom button goes.
  final GuideDestination destination;

  /// Label of the bottom button, e.g. "Open Publish to web".
  final String destinationLabel;

  /// Every string in this guide that may carry markup, in reading order.
  /// Used by the catalog test to check that all copy parses cleanly.
  Iterable<String> get allText sync* {
    yield title;
    yield cardSubtitle;
    yield intro;
    yield* needs;
    for (final section in sections) {
      if (section.hasTitle) yield section.title;
      switch (section) {
        case GuideSteps(:final steps):
          yield* steps;
        case GuideBullets(:final bullets):
          yield* bullets;
        case GuideParagraphs(:final paragraphs):
          yield* paragraphs;
        case GuideTable(:final rows):
          for (final row in rows) {
            yield row.want;
            yield row.use;
          }
      }
    }
    yield* goodToKnow;
    yield destinationLabel;
  }
}
