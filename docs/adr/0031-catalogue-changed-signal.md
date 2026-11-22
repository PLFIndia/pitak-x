# ADR 0031: "Catalogue data changed" is a signal of its own; the Library list keeps its rows and its place

- **Status:** Accepted
- **Date:** 2026-11-22

## Context

The Library list's state did two jobs. It was the list on the screen,
and it was the app's "catalogue data changed" signal: a flow that wrote
catalogue data invalidated or reloaded the list, and everything that
shows catalogue data watched the list. The review of November 2026
lists what followed as three findings:

- **P4-M2.** A reload set the list to "loading", and the screen drew
  that as a spinner in place of the rows. The list left the screen and
  came back at the top: after saving an edited item, after Remove or
  Restore, at every search, chip or sort change. A reload also read at
  most 500 rows.
- **P3-M4.** The list's state also changes when the user only scrolls
  (a page is loaded) or types (a search runs). Eleven places watched
  it, among them the availability updater, which reads the whole
  catalogue while the borrowers vault is unlocked.
- **P4-m13.** The language chips were empty for as long as the
  languages were read again.

What was read (Riverpod 2.6.1, Drift 2.28.2), tried outside git and
looked at on a phone with Android 14 BEFORE the design was final
(`PLAN.md`, D149):

- Whether the place was lost depended on HOW the list was told. A
  reload by hand and a change of the sort or a chip showed the spinner;
  an invalidation kept the rows. The header of the controller promised
  "the list does not jump back to the top" for all of them.
- With the vault unlocked, each page of 60 rows and each typed letter
  read the whole catalogue twice. For 10,000 items that is 0.4 to 0.5
  seconds of reading on a Mac; a phone was not measured.
- On the phone (a fast one, 10,000 made-up items): the list at the top
  after an edit, the chips blinking, and a spinner for a fraction of a
  second while searching with the vault unlocked were seen. A stutter
  while scrolling was not.

## Decision

1. **A signal of its own** (D150):
   `lib/features/library/application/catalogue_changes.dart`, a counter
   that is kept for the whole app run. The Library list is one of its
   listeners, no longer the signal.

2. **The write paths say it, each at the moment it chooses** (D151):
   `ref.read(catalogueChangesProvider.notifier).changed()` after a
   write that succeeded, where the list was invalidated or reloaded
   before. Nothing moved in time: a restore, an import and a merge keep
   the order of their steps. Not chosen: the database's own stream of
   table updates (it fires at each commit, in the middle of a merge and
   after a rollback; a restore does not write through the open
   database, so it would need the signal by hand all the same; and the
   tests' stand-in stores have no database to hear from); a wrapper
   around the repository (inside a transaction it would fire before the
   commit). The new provider is the one place where the database's
   stream could be attached later.

3. **Everything that shows catalogue data watches the signal**: the
   language chips, the export's source picker, an item's page, a loan
   row's title, Borrowed Items, the three series providers, the series
   page's issues, the Magazines list, the availability updater. No
   file outside the Library screen's own code names the list's provider
   any more; a test holds that
   (`test/architecture/catalogue_change_signal_test.dart`, D155).

4. **While the list is read again, its rows stay** (D152). The same
   list after a change: the rows change in place and the list stays
   where it was. Another list (search text, chip, sort): the old rows
   stay until the new ones are there, and the new list starts at the
   top. The spinner is left for the very first load; a read that fails
   shows the error screen as before, and Retry is greyed out while it
   runs. Not chosen: a thin progress bar whenever a read runs (with
   reads this short the bar would itself flicker at every typed
   letter); the spinner kept for a new search (the flash that was seen
   would stay).

5. **The list's state says which question its rows answer.** With the
   old rows kept, an empty list must not explain itself from the search
   box and the chips as they are NOW: "Clear filters" on an empty
   result would show "Your library is empty" until the new rows
   arrive. `LibraryWindow` carries the query it was read for and a
   serial number that goes up when the rows belong to another list; the
   empty state reads the first, the scroll view's key is the second.

6. **After a change the list is read again to where the user was, in
   pieces of 500 rows** (D153). The cap on one read stays (a page read
   can never turn into a whole-catalogue read); a deep list takes
   several reads, and a load that a newer one overtakes stops. On a
   Mac, 10,000 items: to row 2,000 in 34 to 57 ms, to row 9,000 in 175
   to 295 ms. Not chosen: the cap as a limit of the list (past row 500
   the list would land near row 500 after any change).

7. **Nobody waits for the list** (D154). A form says "changed" and
   closes; Remove and Restore on an item's page do the same. The list
   and the page underneath catch up. ADR 0028 (point 3) names three
   forms that reload a list between their save and leaving and mark
   themselves saved for that moment. The book form and the other-item
   form have no such moment any more and no longer call `markSaved()`;
   the wishlist's form still does.

8. **Two things Riverpod does that the list's controller rests on.**
   It refuses `ref.read` while a provider waits for its own rebuild
   (an assert, so in debug builds and tests): a write of the list's
   controller reads what it needs before its first wait. And it
   rebuilds lazily: the answer of a page that was being read asks for
   the state first, so that it sees a newer load that is due.

## Consequences

- A flow that writes catalogue data says `changed()` after its write.
  **No test can hold that for a write path of the future** (a known
  limit, accepted with D151); a list that does not update after a new
  kind of write is the sign.
- A provider that shows catalogue data watches
  `catalogueChangesProvider`. The gate test fails a file that watches,
  listens to or invalidates the Library list instead.
- A test hears the signal without a database: its stand-in store is
  written to, then `changed()` is said.
- Known limits:
  - during a slow read the old rows are looked at with no sign that
    something is coming. Nothing measured says a sign is needed; a
    thin bar after half a second can be added without undoing
    anything;
  - while the read for one typed letter runs and the next letter is
    typed, the rows of the earlier text can show for a moment;
  - while the vault is unlocked the availability updater still reads
    the whole catalogue once for each REAL change (a downloaded cover
    is one); the rows that have loans would do;
  - the Magazines list's state is still used as "the series changed"
    by four providers, which may therefore read more than once for one
    change. That list has no paging, so its state changes only when it
    is really read again;
  - the series page's list of issues is read again in one read of at
    most 500 rows: past issue 500 it would not keep its place after a
    change (from reading, not tried; a series that long is unusual);
  - a slow phone has not been tried.

Looked at before it was accepted (D156). In an emulator of API 36, by
the agent, in a debug build with 10,000 made-up items restored into it
and a made-up vault, the screen read as text: after an edit about 2,100
rows deep the list stood where it was and the row had changed in place,
and the same with the vault unlocked; after Remove, Restore, a form's
save and "Add book" the page underneath was in front within half a
second; a search, a chip and a change of the sort each started at the
top; an empty filtered result gave way to the rows with "Your library
is empty" in no reading; the app's lines of the device log held no
error of the app and no made-up name. Not tried there: the error
screen and its Retry, a read slow enough to see old rows waiting, a
blink of the chips (a reading of the screen cannot see one frame),
smoothness, the grid of a wide screen, a screen reader, the
availability updater (no site was set up). On a phone with Android 14,
by the maintainer, in a release build over an install with 10,000
made-up items and a made-up vault, the steps of the look that was made
before the design and one more: no stutter while scrolling, with the
vault locked or unlocked; after an edit the list "stays there only";
while searching "no blink or spinner", with the vault unlocked too;
about 2,000 rows deep, after an edit, the list "stays there. quick".
Not tried on the phone: a slow phone, a library beyond 10,000 items,
the largest font, a screen reader.
