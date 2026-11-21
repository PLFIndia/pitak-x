/// Tests of the "Discard changes?" guard of the forms (review finding
/// P4-M1; decisions D94 to D97 of PLAN.md).
///
/// Three things are tested, each by itself:
///  - `OpenedValues`: does the form hold something else than it opened with;
///  - the dialog: its words, and that only "Discard" means "leave";
///  - `DiscardChangesGuard`: what Back does on a small probe form that
///    stands above a home page, the way the app's forms do.
///
/// The nine real forms have their own tests; these hold the shared part.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/theme/app_theme.dart';
import 'package:pitaka/core/widgets/discard_changes_guard.dart';

import '../../support/a11y.dart';
import '../../support/form_back_harness.dart';

const String _title = 'Discard changes?';
const String _pageSentence =
    'What you entered on this page has not been saved.';
const String _keep = 'Keep editing';
const String _discard = 'Discard';

/// A form with one text field and the guard around it.
class _ProbeForm extends StatefulWidget {
  const _ProbeForm({this.message, super.key});

  /// The guard's own sentence, or null for the default one.
  final String? message;

  @override
  State<_ProbeForm> createState() => _ProbeFormState();
}

class _ProbeFormState extends State<_ProbeForm> {
  final TextEditingController field = TextEditingController();
  late final OpenedValues _opened;
  bool _saving = false;

  /// How often the form was built: a test uses it to show that a change
  /// reached the guard without a rebuild.
  int builds = 0;

  @override
  void initState() {
    super.initState();
    _opened = OpenedValues(() => [field.text]);
  }

  @override
  void dispose() {
    field.dispose();
    super.dispose();
  }

  /// What a form does while its save runs.
  void showSaving({required bool saving}) => setState(() => _saving = saving);

  /// What every form does after a good save.
  void leaveAsAfterSave() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    builds++;
    final form = Scaffold(
      appBar: AppBar(title: const Text('Probe form')),
      body: TextField(controller: field),
    );
    final message = widget.message;
    return message == null
        ? DiscardChangesGuard(
            hasChanges: () => _opened.changed,
            saving: _saving,
            child: form,
          )
        : DiscardChangesGuard(
            hasChanges: () => _opened.changed,
            saving: _saving,
            message: message,
            child: form,
          );
  }
}

void main() {
  group('OpenedValues', () {
    test('unchanged when made, changed when a value differs, unchanged '
        'again when the value is put back', () {
      final values = <Object?>['title', 1, null, false];
      final opened = OpenedValues(() => List.of(values));
      expect(opened.changed, isFalse);

      values[0] = 'title!';
      expect(opened.changed, isTrue);

      values[0] = 'title';
      expect(opened.changed, isFalse);
    });

    test('a change in any single place is seen', () {
      const before = <Object?>['title', 1, null, false];
      const after = <Object?>['other', 2, 'set', true];
      for (var place = 0; place < before.length; place++) {
        final values = List.of(before);
        final opened = OpenedValues(() => List.of(values));
        values[place] = after[place];
        expect(opened.changed, isTrue, reason: 'place $place');
      }
    });

    test('a form that hands out one and the same list each time is still '
        'seen to change', () {
      // The value keeps a COPY of what it read. Without the copy, "as
      // opened" and "now" would be one list, and nothing could ever differ.
      final values = <Object?>['title'];
      final opened = OpenedValues(() => values);
      values[0] = 'other';
      expect(opened.changed, isTrue);

      // The same after a reset().
      opened.reset();
      expect(opened.changed, isFalse);
      values[0] = 'a third';
      expect(opened.changed, isTrue);
    });

    test('reset() takes the present values as opened', () {
      final values = <Object?>['title', 1];
      final opened = OpenedValues(() => List.of(values));
      values[0] = 'saved title';
      opened.reset();
      expect(opened.changed, isFalse);

      values[0] = 'title';
      expect(opened.changed, isTrue, reason: 'the old value is a change now');
    });

    group('absorb(fill): what the app fills in by itself', () {
      test('the places the fill changed are not a change afterwards', () {
        final values = <Object?>['', '', 1];
        final opened = OpenedValues(() => List.of(values))
          ..absorb(() {
            values[0] = 'Vol. 3';
            values[2] = 4;
          });
        expect(opened.changed, isFalse);
      });

      test('a place the user changed BEFORE the fill stays a change', () {
        final values = <Object?>['', ''];
        final opened = OpenedValues(() => List.of(values));
        values[1] = 'typed by the user';
        // The fill leaves the user's field alone and fills the empty one.
        opened.absorb(() => values[0] = 'Vol. 3');
        expect(opened.changed, isTrue);

        values[1] = '';
        expect(opened.changed, isFalse, reason: 'put back: only the fill left');
      });

      test('a place the fill set and the user then changed is a change', () {
        final values = <Object?>['', ''];
        final opened = OpenedValues(() => List.of(values))
          ..absorb(() => values[0] = 'Vol. 3');
        values[0] = 'Vol. 4';
        expect(opened.changed, isTrue);

        values[0] = 'Vol. 3';
        expect(opened.changed, isFalse, reason: 'back at the suggestion');
      });

      test('a fill that changes nothing leaves everything as it was', () {
        final values = <Object?>['', ''];
        final opened = OpenedValues(() => List.of(values))..absorb(() {});
        expect(opened.changed, isFalse);

        values[0] = 'typed';
        opened.absorb(() {});
        expect(opened.changed, isTrue);
      });
    });

    test('markSaved(): nothing counts as changed afterwards, whatever is '
        'typed', () {
      final values = <Object?>['title'];
      final opened = OpenedValues(() => List.of(values));
      values[0] = 'new title';
      expect(opened.changed, isTrue);

      opened.markSaved();
      expect(opened.changed, isFalse);

      // A letter typed in the moment between the save and the page leaving.
      values[0] = 'new title, and more';
      expect(opened.changed, isFalse);
    });
  });

  group('the dialog', () {
    /// What each closed dialog answered, in order.
    late List<bool> answers;

    setUp(() => answers = <bool>[]);

    /// A page with one button that opens the dialog.
    Widget host({String? message, ThemeData? theme}) => MaterialApp(
      theme: theme,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async {
                answers.add(
                  message == null
                      ? await showDiscardChangesDialog(context)
                      : await showDiscardChangesDialog(
                          context,
                          message: message,
                        ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    Future<void> open(WidgetTester tester) async {
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('shows the words that were decided (D96), and "Discard" '
        'answers yes', (tester) async {
      await tester.pumpWidget(host());
      await open(tester);

      expect(find.text(_title), findsOneWidget);
      expect(find.text(_pageSentence), findsOneWidget);
      expect(find.widgetWithText(TextButton, _keep), findsOneWidget);
      expect(find.widgetWithText(FilledButton, _discard), findsOneWidget);

      await tester.tap(find.text(_discard));
      await tester.pumpAndSettle();
      expect(answers, [true]);
      expect(find.text(_title), findsNothing);
    });

    testWidgets('"Keep editing" answers no', (tester) async {
      await tester.pumpWidget(host());
      await open(tester);
      await tester.tap(find.text(_keep));
      await tester.pumpAndSettle();

      expect(answers, [false]);
    });

    testWidgets('a tap beside the dialog answers no', (tester) async {
      await tester.pumpWidget(host());
      await open(tester);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      expect(answers, [false]);
    });

    testWidgets('Back while it is open answers no', (tester) async {
      await tester.pumpWidget(host());
      await open(tester);
      await pressSystemBack(tester);

      expect(answers, [false]);
    });

    testWidgets('a sentence that is handed in replaces the usual one', (
      tester,
    ) async {
      await tester.pumpWidget(host(message: 'A sentence of the caller.'));
      await open(tester);

      expect(find.text('A sentence of the caller.'), findsOneWidget);
      expect(find.text(_pageSentence), findsNothing);
      expect(find.text(_title), findsOneWidget);
    });

    for (final (name, theme) in [
      ('light', AppTheme.light),
      ('dark', AppTheme.dark),
    ]) {
      testWidgets("meets accessibility guidelines in the app's $name theme", (
        tester,
      ) async {
        await tester.pumpWidget(host(theme: theme));
        await open(tester);

        await expectMeetsA11yGuidelines(tester);
      });
    }

    for (final (name, size, pixelRatio, textScale) in const [
      // The phone size of the golden tests (411 x 914 dp).
      ('a phone, text twice as large', Size(1080, 2400), 2.625, 2.0),
      // The harsh case of the resource notice's test: the words are then
      // taller than the screen, and the dialog has to scroll.
      ('a small phone, text three times as large', Size(320, 480), 1.0, 3.0),
    ]) {
      testWidgets('on $name nothing overflows and both buttons can be '
          'tapped', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = pixelRatio;
        tester.platformDispatcher.textScaleFactorTestValue = textScale;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        await tester.pumpWidget(host());
        await open(tester);

        expect(tester.takeException(), isNull, reason: 'no overflow');
        expect(find.text(_keep).hitTestable(), findsOneWidget);
        expect(find.text(_discard).hitTestable(), findsOneWidget);
        await tester.tap(find.text(_discard));
        await tester.pumpAndSettle();
        expect(answers, [true]);
      });
    }
  });

  group('the guard, on a form above a home page', () {
    late GlobalKey<_ProbeFormState> form;

    setUp(() => form = GlobalKey<_ProbeFormState>());

    Future<void> openForm(WidgetTester tester, {String? message}) async {
      await pumpFormAboveHome(tester, _ProbeForm(key: form, message: message));
      expect(find.text('Probe form'), findsOneWidget);
    }

    void expectFormIsGone() {
      expect(find.text('Probe form'), findsNothing);
      expect(findFormBackHome(), findsOneWidget);
    }

    void expectFormStays() {
      expect(find.text('Probe form'), findsOneWidget);
      expect(findFormBackHome(), findsNothing);
    }

    testWidgets('untouched, Back: the form leaves at once, no question', (
      tester,
    ) async {
      await openForm(tester);
      await pressSystemBack(tester);

      expect(find.text(_title), findsNothing);
      expectFormIsGone();
    });

    testWidgets('untouched, the arrow of the app bar: the same', (
      tester,
    ) async {
      await openForm(tester);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.text(_title), findsNothing);
      expectFormIsGone();
    });

    testWidgets('changed, Back: the question. "Keep editing" keeps the form '
        'and the text; Back again and "Discard" leaves that one page', (
      tester,
    ) async {
      await openForm(tester);
      await tester.enterText(find.byType(TextField), 'typed');
      await pressSystemBack(tester);

      expect(find.text(_title), findsOneWidget);
      expect(find.text(_pageSentence), findsOneWidget);

      await tester.tap(find.text(_keep));
      await tester.pumpAndSettle();
      expect(find.text(_title), findsNothing);
      expectFormStays();
      expect(find.text('typed'), findsOneWidget);

      await pressSystemBack(tester);
      await tester.tap(find.text(_discard));
      await tester.pumpAndSettle();
      expect(find.text(_title), findsNothing);
      // The form is gone and the home page is still there: one page left.
      expectFormIsGone();
    });

    testWidgets('changed, the arrow of the app bar: the question', (
      tester,
    ) async {
      await openForm(tester);
      await tester.enterText(find.byType(TextField), 'typed');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.text(_title), findsOneWidget);
      expectFormStays();
    });

    testWidgets('typed and put back, Back: leaves, no question', (
      tester,
    ) async {
      await openForm(tester);
      await tester.enterText(find.byType(TextField), 'typed');
      await tester.enterText(find.byType(TextField), '');
      await pressSystemBack(tester);

      expect(find.text(_title), findsNothing);
      expectFormIsGone();
    });

    testWidgets("the form's own pop(), as after a save, leaves with no "
        'question although the form is changed', (tester) async {
      await openForm(tester);
      await tester.enterText(find.byType(TextField), 'typed');
      form.currentState!.leaveAsAfterSave();
      await tester.pumpAndSettle();

      expect(find.text(_title), findsNothing);
      expectFormIsGone();
    });

    testWidgets('while a save runs, Back and the arrow do nothing (D95)', (
      tester,
    ) async {
      await openForm(tester);
      await tester.enterText(find.byType(TextField), 'typed');
      form.currentState!.showSaving(saving: true);
      await tester.pump();

      await pressSystemBack(tester);
      expect(find.text(_title), findsNothing);
      expectFormStays();

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text(_title), findsNothing);
      expectFormStays();
    });

    testWidgets('while a save runs, Back does nothing on an unchanged form '
        'either', (tester) async {
      await openForm(tester);
      form.currentState!.showSaving(saving: true);
      await tester.pump();
      await pressSystemBack(tester);

      expectFormStays();
    });

    testWidgets('after a save that failed, Back asks again', (tester) async {
      await openForm(tester);
      await tester.enterText(find.byType(TextField), 'typed');
      form.currentState!.showSaving(saving: true);
      await tester.pump();
      await pressSystemBack(tester);
      expect(find.text(_title), findsNothing);

      form.currentState!.showSaving(saving: false);
      await tester.pump();
      await pressSystemBack(tester);
      expect(find.text(_title), findsOneWidget);
      expectFormStays();
    });

    testWidgets('Back while the question is open closes the question; the '
        'form and its text stay, and the next Back asks once', (tester) async {
      await openForm(tester);
      await tester.enterText(find.byType(TextField), 'typed');
      await pressSystemBack(tester);
      expect(find.text(_title), findsOneWidget);

      await pressSystemBack(tester);
      expect(find.text(_title), findsNothing);
      expectFormStays();
      expect(find.text('typed'), findsOneWidget);

      await pressSystemBack(tester);
      expect(find.text(_title), findsOneWidget, reason: 'one question only');
    });

    testWidgets('the change is read at the moment of Back: a change that '
        'rebuilt nothing still asks', (tester) async {
      await openForm(tester);
      final buildsBefore = form.currentState!.builds;
      // No setState and no onChanged: the form does not learn of this.
      form.currentState!.field.text = "set behind the form's back";
      await tester.pump();
      expect(form.currentState!.builds, buildsBefore);

      await pressSystemBack(tester);
      expect(find.text(_title), findsOneWidget);
    });

    testWidgets("the guard's own sentence reaches the dialog", (tester) async {
      await openForm(tester, message: 'A sentence of this form.');
      await tester.enterText(find.byType(TextField), 'typed');
      await pressSystemBack(tester);

      expect(find.text(_title), findsOneWidget);
      expect(find.text('A sentence of this form.'), findsOneWidget);
      expect(find.text(_pageSentence), findsNothing);
    });

    testWidgets('the form is removed while the question is open, then '
        '"Discard": nothing else is popped and nothing throws', (tester) async {
      await openForm(tester);
      await tester.enterText(find.byType(TextField), 'typed');
      await pressSystemBack(tester);
      expect(find.text(_title), findsOneWidget);

      // Something else takes the form away under the open question.
      tester
          .state<NavigatorState>(find.byType(Navigator))
          .removeRoute(ModalRoute.of(form.currentContext!)!);
      await tester.pumpAndSettle();
      expect(form.currentContext, isNull, reason: 'the form is gone');
      expect(find.text(_title), findsOneWidget);

      await tester.tap(find.text(_discard));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text(_title), findsNothing);
      // Only the question was closed: the home page was not popped too.
      expect(findFormBackHome(), findsOneWidget);
    });
  });
}
