/// Line caps for the text on library catalogue cards — one place, so the
/// list row, the grid card and the grid's height calculation agree.
///
/// Chosen with the maintainer (2026-11-09): with the text column at full
/// width, three title lines and two author lines fit nearly every real
/// title and multi-author name. The shelf line has its own cap
/// (`ShelfLocationLine.maxLines`). Anything longer still ends in "…"; the
/// detail page and screen readers always have the full text.
library;

/// Shared line caps for catalogue cards.
abstract final class CatalogueCardText {
  /// Most lines a title may take.
  static const int titleMaxLines = 3;

  /// Most lines an author may take.
  static const int authorMaxLines = 2;
}
