# ADR 0028: Forms ask before Back throws away unsaved input

- **Status:** Accepted
- **Date:** 2026-11-20

## Context

Back closed a half-filled form at once. One slip of the thumb at the
screen's edge (Android's back gesture), or a tap on the arrow of the app
bar, and a typed title, author and notes were gone. The review of November
2026 lists it as finding P4-M1 and names nine forms: book, other item,
magazine title, magazine issue, wishlist entry, borrower, lend, reminder
template, and "Basic info" of the Publish page.

Four facts of the code and of Flutter shaped the answer:

- Most fields of a form tell nobody when they change, and a text field
  reports even a mere tap into it (the place of the cursor is part of its
  value).
- Three forms (book, other item, wishlist entry) reload a list between a
  good save and leaving the screen. A question that opened in that moment
  would be closed by the form's own leaving, and the form would stay on
  the screen, saved and looking unsaved.
- "Basic info" is a tab, not a page. A tab view throws away the state of a
  tab that is not on the screen, so a look at another tab lost the edits
  as well.
- On Android 16 the app shows the system's back preview while the finger
  swipes. Once a preview has started, lifting the finger closes the page
  without asking it (Flutter 3.44, `widgets/routes.dart`: the gesture ends
  in the plain `pop`).

The decisions were taken one at a time (`PLAN.md`, D93 to D101).

## Decision

1. **One guard for every form** (D93, D96):
   `lib/core/widgets/discard_changes_guard.dart`. `DiscardChangesGuard`
   stands around a form's page. It takes the gesture, the system's button
   and the arrow of the app bar, and asks "Discard changes?" with "Keep
   editing" and "Discard". A tap beside the question, or Back while it is
   open, means "stay". The pattern is the Flutter SDK's own example for
   `PopScope` (`examples/api/lib/widgets/pop_scope/pop_scope.0.dart`).
   The question shows fixed words only, never what was typed.

2. **A change is a difference, not a touch** (D94). `OpenedValues` reads
   what the form's Save would store when the form opens, and again when
   Back is pressed, and compares the two. Typed and put back is no change.
   What the app fills in by itself (the issue form's suggestion from the
   last issue) counts as "opened"; what a lookup filled in is a change.
   Not chosen: a hook on every field ("was anything touched"), which
   silently misses a field that is added later.

3. **Back does nothing while a save runs** (D95). A save that has started
   cannot be taken back, so "Discard" would be a promise the app cannot
   keep. After a good save the form leaves by itself; the three forms
   with a reload mark themselves saved first, so that nothing typed in
   that moment counts (`markSaved()`, D101). Cost, accepted: if a save
   ever hung, Back would stay dead on that page until the app is left
   through Home. Every save of the nine forms is local (the catalogue,
   the vault, the settings), with no network in it.

4. **The guard always answers "ask me first" and decides when Back comes**
   (D97): `canPop` is always false, and an unchanged form is left by the
   guard itself. Cost, accepted: on Android 16 the nine form screens show
   no back preview, even when untouched; the Publish page from the moment
   "Basic info" has been shown. Not chosen: allowing Back while a form is
   unchanged. A preview that starts on an unchanged form could then
   finish, without a question, after the form has changed (the answer of
   a lookup arriving while the finger is down, for one).

5. **"Basic info" keeps its state while the Publish page is open, and
   asks from every tab** (D93). The tab keeps itself alive
   (`AutomaticKeepAliveClientMixin`), so a change of tab no longer throws
   the edits away. Its question has a sentence of its own that names the
   tab, because it can come up while another tab is showing. In view mode
   nothing counts as changed; a round of editing is measured from the tap
   on "Edit".

6. **No guard, on purpose** (D98): passphrase fields (the guard keeps a
   copy of a form's values, and nothing may keep a typed passphrase),
   dialogs with their own Cancel, search fields, the paste box of Import,
   and single settings with their own Save.
   `test/architecture/form_discard_guard_test.dart` lists each such file
   with its reason. It fails when a file under `lib/` creates a text
   controller and neither uses the guard nor is on the list, when the
   list is no longer true, and when a file that handles a passphrase
   uses `OpenedValues`.

## Consequences

- A new form goes inside the guard and hands it one function that lists
  what its Save would store. Its tests type into every field once: a
  field that is forgotten in that list fails them.
- While a form is open, the guard holds a second copy of its values in
  memory. For the borrower form these are a name and contact details,
  which the unlocked vault and the page's own fields hold already. The
  copy goes with the page. Nothing is written to storage or to a log.
- Known limits:
  - the two costs above: Back is dead during a save that hangs, and the
    nine screens have no back preview on Android 16;
  - a phone that ends the app, or restarts its screen, while a form is
    open still loses what was typed (seen in an emulator: changing the
    navigation mode in the system's Settings restarts the screen);
  - the test sees a file that creates a text controller. A form that
    kept its text in some other way would not be seen (none does);
  - a double tap on Save can still save twice (review finding P4-m2, a
    finding of its own).
- Not tried: iOS and the desktop builds. By the SDK's own words a page
  with `canPop` false has no swipe-back on iOS at all. The app ships on
  Android.

**Seen on devices (2026-11-20).** In an emulator with Android 16: Back and
the back gesture ask on a changed form and leave an untouched one; the
first Back closes the keyboard; the item's page shows the back preview and
the book form shows none; "Basic info" keeps an edit across a change of
tab and asks from another tab. On a phone with Android 14: judged by the
maintainer, also with the largest font and in the dark theme.
