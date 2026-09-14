/// The library "visiting card" (presentation, AGENTS.md §3.1).
///
/// A fixed 1050×600 logical-pixel card, rendered identically in the live
/// preview (scaled down inside a `FittedBox`) and in the captured PNG:
///
/// ```text
/// ┌──────────────────────────────────────────────┬─────────┐
/// │ [logo]  Library name                         │  [QR]   │
/// │         Address line(s)                      │ SCAN TO │
/// │                                              │  VISIT  │
/// │ user.github.io/library                       │         │
/// ├──────────────────────────────────────────────┴─────────┤
/// │ Made with  [Pitak]  Pitak / A community library app     │
/// └────────────────────────────────────────────────────────┘
/// ```
///
/// Four palettes ([ShareCardStyle]) share this one layout. Text scaling is
/// pinned (`MediaQuery.withNoTextScaling`) so the PNG does not change with
/// the phone's accessibility font size — the card is an artefact, not UI.
library;

import 'package:flutter/material.dart';
import 'package:pitaka/core/widgets/library_logo.dart';
import 'package:pitaka/core/widgets/qr_view.dart';
import 'package:pitaka/features/publish/domain/share_card_style.dart';

/// Colour set for one [ShareCardStyle]. Presentation-only (uses `Color`).
@immutable
class ShareCardPalette {
  /// Creates a palette.
  const ShareCardPalette({
    required this.background,
    required this.text,
    required this.muted,
    required this.link,
    required this.logoTile,
    required this.logoTileText,
    required this.footerBackground,
    required this.divider,
    this.frame,
    this.band,
  });

  /// Resolves the palette for [style]. Values mirror the approved HTML
  /// mockups (rev 2); indigo = the app seed colour, orange = the Pitak icon.
  ///
  /// A factory (not a static method) so the lint's "constructors over static
  /// methods" rule and the call-site shape `ShareCardPalette.of(style)` agree.
  factory ShareCardPalette.of(ShareCardStyle style) => switch (style) {
    ShareCardStyle.classic => const ShareCardPalette(
      background: Color(0xFFFFFFFF),
      text: Color(0xFF1C1B1F),
      muted: Color(0xFF5F5E66),
      link: Color(0xFF3F51B5),
      logoTile: Color(0xFFE8E6FF),
      logoTileText: Color(0xFF3F51B5),
      footerBackground: Color(0xFFFFFFFF),
      divider: Color(0x14000000),
    ),
    ShareCardStyle.dark => const ShareCardPalette(
      background: Color(0xFF1C1B2A),
      text: Color(0xFFF4F2FA),
      muted: Color(0xFFB8B6C4),
      link: Color(0xFFB9C1FF),
      logoTile: Color(0xFF3F51B5),
      logoTileText: Color(0xFFFFFFFF),
      footerBackground: Color(0xFF1C1B2A),
      divider: Color(0x1FFFFFFF),
    ),
    ShareCardStyle.gradient => const ShareCardPalette(
      background: Color(0xFFFFFFFF),
      text: Color(0xFF1C1B1F),
      muted: Color(0xFF5F5E66),
      link: Color(0xFF3F51B5),
      logoTile: Color(0xFF3F51B5),
      logoTileText: Color(0xFFFFFFFF),
      footerBackground: Color(0xFFF5F4FB),
      divider: Color(0x00000000),
      band: LinearGradient(colors: [Color(0xFF3F51B5), Color(0xFFE2542A)]),
    ),
    ShareCardStyle.framed => const ShareCardPalette(
      background: Color(0xFFFBF7F2),
      text: Color(0xFF2B241F),
      muted: Color(0xFF6B625A),
      link: Color(0xFF3F51B5),
      logoTile: Color(0xFFE2542A),
      logoTileText: Color(0xFFFFFFFF),
      footerBackground: Color(0xFFFBF7F2),
      divider: Color(0x593F51B5),
      frame: Color(0xFF3F51B5),
    ),
  };

  /// Card background.
  final Color background;

  /// Primary text (library name, address).
  final Color text;

  /// Secondary text ("Made with", QR caption, tagline).
  final Color muted;

  /// Link text colour.
  final Color link;

  /// Monogram tile background.
  final Color logoTile;

  /// Monogram letters.
  final Color logoTileText;

  /// Footer strip background (may equal [background]).
  final Color footerBackground;

  /// Line between body and footer.
  final Color divider;

  /// Thick outer frame (Framed style only).
  final Color? frame;

  /// Gradient band across the top (Gradient style only).
  final Gradient? band;
}

/// The visiting card. Always lays out at [width]×[height]; wrap it in a
/// `FittedBox` to preview at any smaller size.
class LibraryShareCard extends StatelessWidget {
  /// Creates the card.
  const LibraryShareCard({
    required this.style,
    required this.libraryName,
    required this.address,
    required this.url,
    super.key,
  });

  /// Design width in logical pixels (7:4, business-card proportions).
  static const double width = 1050;

  /// Design height in logical pixels.
  static const double height = 600;

  /// Corner radius of the whole card.
  static const double radius = 24;

  /// Pitak's brand orange (the icon's background), used for the wordmark.
  static const Color pitakOrange = Color(0xFFE2542A);

  /// Which palette to paint.
  final ShareCardStyle style;

  /// Raw library name (blank → "My Library").
  final String libraryName;

  /// Raw public address (blank → line omitted).
  final String address;

  /// Full published URL — encoded verbatim into the QR.
  final String url;

  @override
  Widget build(BuildContext context) {
    final palette = ShareCardPalette.of(style);
    final name = ShareCardText.displayName(libraryName);
    final trimmedAddress = address.trim();
    final frameWidth = palette.frame == null ? 0.0 : 14.0;

    return MediaQuery.withNoTextScaling(
      child: SizedBox(
        width: width,
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.frame ?? palette.background,
            borderRadius: BorderRadius.circular(radius),
          ),
          child: Padding(
            padding: EdgeInsets.all(frameWidth),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(radius - frameWidth),
              child: ColoredBox(
                color: palette.background,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (palette.band != null)
                      Container(
                        height: 18,
                        decoration: BoxDecoration(gradient: palette.band),
                      ),
                    Expanded(
                      child: _Body(
                        palette: palette,
                        name: name,
                        address: trimmedAddress,
                        url: url,
                        // Slightly less top padding when the band eats 18px.
                        topPadding: palette.band == null ? 56 : 44,
                      ),
                    ),
                    _Footer(palette: palette),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.palette,
    required this.name,
    required this.address,
    required this.url,
    required this.topPadding,
  });

  final ShareCardPalette palette;
  final String name;
  final String address;
  final String url;
  final double topPadding;

  static const double _logoSize = 120;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(60, topPadding, 60, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Logo + name share one 120px-tall row (the user's spec).
                SizedBox(
                  height: _logoSize,
                  child: Row(
                    children: [
                      LibraryLogo(
                        size: _logoSize,
                        borderRadius: 24,
                        fallback: _MonogramTile(
                          palette: palette,
                          letters: ShareCardText.monogram(name),
                          size: _logoSize,
                        ),
                      ),
                      const SizedBox(width: 26),
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: palette.text,
                            fontSize: 48,
                            height: 1.12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (address.isNotEmpty) ...[
                  const SizedBox(height: 34),
                  Text(
                    address,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.text,
                      fontSize: 27,
                      height: 1.35,
                    ),
                  ),
                ],
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.only(bottom: 36),
                  child: Text(
                    ShareCardText.displayUrl(url),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.link,
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 48),
          _QrColumn(palette: palette, url: url),
        ],
      ),
    );
  }
}

class _MonogramTile extends StatelessWidget {
  const _MonogramTile({
    required this.palette,
    required this.letters,
    required this.size,
  });

  final ShareCardPalette palette;
  final String letters;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: palette.logoTile,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Text(
        letters,
        style: TextStyle(
          color: palette.logoTileText,
          fontSize: 46,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

class _QrColumn extends StatelessWidget {
  const _QrColumn({required this.palette, required this.url});

  final ShareCardPalette palette;
  final String url;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // QR sits on its own white tile in every palette so scanners get a
        // clean quiet zone even on the dark card.
        Container(
          width: 270,
          height: 270,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: palette.frame != null
                ? Border.all(color: palette.frame!, width: 3)
                : Border.all(color: palette.divider, width: 2),
          ),
          child: QrView(data: url, size: 254),
        ),
        const SizedBox(height: 14),
        Text(
          'SCAN TO VISIT',
          style: TextStyle(
            color: palette.muted,
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 2.2,
          ),
        ),
      ],
    );
  }
}

/// "Made with · (icon) Pitak / A community library app". The wordmark and
/// tagline are stacked to exactly the icon's height (user spec).
class _Footer extends StatelessWidget {
  const _Footer({required this.palette});

  final ShareCardPalette palette;

  static const double _iconSize = 42;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 84,
      padding: const EdgeInsets.symmetric(horizontal: 60),
      decoration: BoxDecoration(
        color: palette.footerBackground,
        border: Border(top: BorderSide(color: palette.divider)),
      ),
      child: Row(
        children: [
          Text(
            'Made with',
            style: TextStyle(color: palette.muted, fontSize: 15),
          ),
          const SizedBox(width: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.asset(
              kDefaultLogoAsset,
              width: _iconSize,
              height: _iconSize,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            height: _iconSize,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Pitak',
                  style: TextStyle(
                    color: LibraryShareCard.pitakOrange,
                    fontSize: 21,
                    height: 1,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'A community library app',
                  style: TextStyle(
                    color: palette.muted,
                    fontSize: 12,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
