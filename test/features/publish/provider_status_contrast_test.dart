/// Review item 13: every provider-status colour must reach 4.5:1 on the
/// ACTUAL card colour of both app themes — not on an assumed white. The
/// status labels are small bold text, so WCAG's small-text threshold applies.
/// Light green 700 / amber 800 / blue 700 all failed on the real card.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/theme/app_theme.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_connection_ui.dart';
import 'package:pitaka/features/publish/application/github_connection_ui.dart';
import 'package:pitaka/features/publish/presentation/widgets/cloudflare_tile.dart';
import 'package:pitaka/features/publish/presentation/widgets/github_tile.dart';
import 'package:pitaka/features/publish/presentation/widgets/provider_tile.dart';

import '../../support/a11y.dart';
import 'support/cloudflare_fakes.dart';

const _minimum = 4.5;

/// The colour a [Card] actually paints under [theme] (M3: the card theme's
/// colour when set, else `surfaceContainerLow`).
Color _cardColor(ThemeData theme) =>
    theme.cardTheme.color ?? theme.colorScheme.surfaceContainerLow;

Widget _themed(ThemeData theme, Widget child) => MaterialApp(
  theme: theme,
  home: Scaffold(body: child),
);

void main() {
  final themes = <String, ThemeData>{
    'light': AppTheme.light,
    'dark': AppTheme.dark,
  };

  group('measured colour pairs on the real card colour', () {
    for (final MapEntry(key: name, value: theme) in themes.entries) {
      final card = _cardColor(theme);
      final brightness = theme.brightness;

      for (final config in ProviderConfig.values) {
        test('$name: ${config.label} ≥ $_minimum:1', () {
          final ratio = contrastRatio(config.color(brightness), card);
          expect(
            ratio,
            greaterThanOrEqualTo(_minimum),
            reason:
                '${config.name} on $name card is ${ratio.toStringAsFixed(2)}',
          );
        });
      }

      test('$name: Signed in / Token verified use the success colour', () {
        final ratio = contrastRatio(
          ProviderStatusColors.success(brightness),
          card,
        );
        expect(ratio, greaterThanOrEqualTo(_minimum));
      });
    }

    test('dark shades are the long-standing tints (not regressed)', () {
      expect(ProviderStatusColors.success(Brightness.dark), Colors.green[400]);
      expect(ProviderStatusColors.warning(Brightness.dark), Colors.amber[300]);
      expect(ProviderStatusColors.info(Brightness.dark), Colors.lightBlue[300]);
      expect(ProviderStatusColors.error(Brightness.dark), Colors.red[300]);
    });
  });

  group('rendered tiles pass the text-contrast guideline', () {
    for (final MapEntry(key: name, value: theme) in themes.entries) {
      testWidgets('$name: the pumped card paints the colour the pairs assume', (
        tester,
      ) async {
        await tester.pumpWidget(
          _themed(
            theme,
            const ProviderTile(
              title: 'Provider',
              status: ProviderConfig.configured,
              body: Text('body'),
            ),
          ),
        );
        final material = tester.widget<Material>(
          find.descendant(
            of: find.byType(Card),
            matching: find.byType(Material),
          ),
        );
        expect(material.color, _cardColor(theme));
      });

      for (final config in ProviderConfig.values) {
        for (final expanded in [false, true]) {
          testWidgets(
            '$name: ${config.label} ${expanded ? 'expanded' : 'collapsed'}',
            (tester) async {
              await tester.pumpWidget(
                _themed(
                  theme,
                  ProviderTile(
                    title: 'Provider',
                    status: config,
                    initiallyExpanded: expanded,
                    body: const Text('Settings body'),
                  ),
                ),
              );
              await tester.pumpAndSettle();
              expect(find.text(config.label), findsOneWidget);
              await expectMeetsTextContrast(tester);
            },
          );
        }
      }

      testWidgets('$name: GitHub "Signed in" row, expanded', (tester) async {
        await tester.pumpWidget(
          _themed(
            theme,
            GitHubTile(
              ui: const GitHubConnectionUi(
                signedIn: true,
                targetRepo: 'owner/repo',
              ),
              initiallyExpanded: true,
              onSignIn: () {},
              onSignOut: () {},
              onRequestRepoSetup: () {},
              onLoadRepos: () {},
              onSelectRepo: (_) {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Signed in'), findsOneWidget);
        await expectMeetsTextContrast(tester);
      });

      testWidgets('$name: Cloudflare "Token verified" row, expanded', (
        tester,
      ) async {
        await tester.pumpWidget(
          _themed(
            theme,
            CloudflareTile(
              ui: CloudflareConnectionUi(
                status: cloudflareTestConnection().status,
              ),
              onConnect: () {},
              onContinue: () {},
              onDisconnect: () {},
              onForgetConnection: () {},
              onCancelSetup: () {},
            ),
          ),
        );
        await tester.tap(find.text('Cloudflare Workers'));
        await tester.pumpAndSettle();
        expect(find.text('Token verified'), findsOneWidget);
        await expectMeetsTextContrast(tester);
      });
    }
  });
}
