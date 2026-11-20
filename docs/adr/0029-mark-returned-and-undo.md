# ADR 0029: "Mark returned" where the user stands, and a return can be taken back

- **Status:** Accepted
- **Date:** 2026-11-20

## Context

A book comes back. The user opened Borrowed Items, found the card, and
saw no way to say so. A tap on the card led to the item's page, which
said "Mark it returned before lending it again" and offered no button.
The real path was the menu, the borrowers vault, the borrower, "Return".
A wrong tap there could not be taken back: no question, no undo. The
review of November 2026 lists it as finding P4-M3.

Five facts of the code and of Flutter shaped the answer:

- The return was written in two widgets, each from the copy of the loan
  it was drawn with, through a method that stored whatever row it was
  handed and checked nothing.
- A loan could not be made "not returned" again in Dart at all:
  `Loan.copyWith` keeps the old value when it is given none.
- An item can have several copies, so it can be out with several
  borrowers at once.
- Taking a return back makes a loan active again. If the same copy was
  lent to somebody else in between, one copy would be out twice.
- A bar at the bottom of the screen (a snackbar) belongs to the app, not
  to the page that showed it. It is still there after Back, and its
  button still works. The app's messages wait in ONE line: a bar that
  stays keeps every later message unseen. And since Flutter 3.38 a bar
  with a button stays until it is used, unless it is told otherwise
  (Flutter 3.44, `material/snack_bar.dart`, `persist`).

The decisions were taken one at a time (`PLAN.md`, D103 to D114).

## Decision

1. **"Mark returned" stands in three places and is one piece of code**
   (D103, D109): on the loan card of Borrowed Items, on the item's page
   (one line for each loan of the item that is out), and on the
   borrower's profile. The words are the same everywhere; "Return" on a
   button can be read as "go back". The gesture, its bar and its
   sentences are in
   `lib/features/vault/presentation/widgets/loan_return_action.dart`.

2. **A return and its taking-back are one operation of the application
   layer** (D107, D110): `change_loan_return.dart`, reached only through
   `VaultSessionController.setLoanReturned`, inside the session's queue.
   A screen hands in the loan's id, never a row. The operation reads the
   loan as it is now. A loan that is already in the state asked for is a
   success without a write, so two fast taps are one return with one
   date. The controller's `updateLoan` and `deleteLoan`, which wrote
   whatever they were handed, are gone. No screen can change a loan's
   date of return any other way: the session has no other method for it,
   and only the session holds the vault's key.

3. **Taking a return back checks one thing: a copy is still free**
   (D107; `domain/loan_return.dart`). If the item was lent again in the
   meantime, it refuses with a sentence and writes nothing. It does not
   check the borrower limit or "removed from the library". It corrects a
   record, it does not lend: a rule that refused the correction would
   leave a wrong return standing.

4. **No question before a return. "Undo" for six seconds, and a lasting
   way back beside it** (D105, D114). After a return a bar says "Marked
   returned." and offers "Undo". The bar is timed. Whoever misses it
   opens the borrower's page: under "History" every returned loan has
   "Not returned", which asks first ("Mark as not returned?") and then
   puts the loan back with the dates it had. Both run the same operation.
   Not chosen: a bar that stays until it is used (first decided as D106,
   then found in a trial to hold back every other message of the app for
   as long as it stays, a failure message among them); a question before
   every return (five books, ten taps, and a wrong "yes" still could not
   be taken back); a banner at the top that stays on every page.

5. **The bar names nobody, and what names a borrower needs the vault
   unlocked now** (D104, with D84). The sentences of the bar and of the
   question are fixed words: no borrower, no title. The bar is taken off
   the screen the moment the vault stops being unlocked. A line on the
   item's page names the borrower ("Lent to Asha · due 12 November
   2026"), so it is drawn only while the vault is unlocked now; a session
   that is loading again and still carries an earlier unlock draws none
   (`item_active_loans.dart`). Screen-capture protection is on whenever
   the vault is unlocked, as before.

6. **One file reads Riverpod's container itself** (D113), the one step
   outside the rule that the UI reads state through a page's `ref`
   (`AGENTS.md` §4). The bar outlives the page that showed it, and a
   page's `ref` ends with the page, so "Undo" takes what it needs from
   the app's container before the first wait
   (`ProviderScope.containerOf`). Not chosen: a widget at the app's root
   that owns the bar, with a provider that holds "the last return": more
   parts to keep in step for the same effect.

7. **The loan list leaves the Edit borrower form** (D108; the part of
   finding P4-m5 that the review names with P4-M3). A form is for the
   borrower's details. Its "Return" had no sign of working and called a
   loan "Item #12"; the profile, one tap away, shows the same loans with
   their titles.

8. **A failure gets a fixed sentence.** The vault's core answers its own
   validation texts, which are written for developers. The helper shows
   a text from below only when it is the one sentence of decision 3.

## Consequences

- This is the app's first "Undo". The next one follows the pattern: a
  timed bar, never one that stays; the button holds what it needs by
  itself, because its page may be gone; a lasting way back beside the
  bar; no personal data in the bar; and, where vault data is behind it,
  the bar goes with the lock.
- A new place for "Mark returned" uses `MarkReturnedButton`. In a list,
  each row gets a key made of its loan's id: the button keeps "I am
  waiting" in its own state, and without the key that state would stay
  with the row's place instead of with its loan.
- Which loans the item's page shows, and in which order, is a rule in
  the domain (`domain/item_active_loans.dart`), not in the widget.
- Known limits:
  - only the last return can be taken back from the bar: a second return
    takes the first bar's place. The others go through "History";
  - a user of a screen reader gets the same six seconds (Flutter gives a
    timed bar no extra time), and has "History" as well;
  - the loan card has one busy state for all its buttons, so while a
    return is written the spinner shows on the card's share button;
  - the two ways back show no sign of working while the vault writes:
    the bar goes the moment "Undo" is tapped, and "Not returned" stands
    unchanged after its question (a second yes in that time writes
    nothing and says "The loan is open again." once more). Today a save
    in the vault can take seconds on a slow phone (review finding
    P3-M3). The stage that takes that wait away is the next one of the
    plan (`PLAN.md`, D123); this limit is looked at again with it;
  - with the fast lane on (ADR 0019), a return is published after 20
    seconds. A return that is taken back inside that time leaves the
    published list as it was; whether one write is still sent then was
    not read to its end. The published data is right either way;
  - with Android's font size at its largest, on a screen 320 dp wide, the
    words "Mark returned" take two lines on the loan card, where the
    cover leaves them 180 dp; nothing is cut. Everywhere else that was
    looked at they take one line (see "Seen on devices"). The widget
    tests cannot say this: their font draws every letter as a square,
    and there the words take two lines at twice the text size on every
    screen. The tests hold that nothing overflows and that no button
    leaves the screen;
  - "Delete" on a borrower still shows no sign of working while the
    vault writes (the other half of finding P4-m5, not part of this).
- Not tried: iOS and the desktop builds. The app ships on Android.
- What holds it in place: the tests of the rule, of the operation and of
  the gesture (`test/features/vault/loan_return_test.dart`,
  `change_loan_return_test.dart`, `loan_return_action_test.dart`), of
  each of the three screens (`borrowed_items_return_test.dart`,
  `test/features/library/catalogue_item_loans_test.dart`,
  `borrower_profile_page_test.dart`), and a test that holds the in-app
  guide to the buttons' own words (`guide_catalog_test.dart`).

**Seen on devices (2026-11-20).** In an emulator with Android 16, with
made-up books and borrowers, read from the screen's accessibility tree
(while the vault is unlocked a screenshot comes out blank on every page:
the screen-capture protection at work): the button on the loan card, on
the item's page with one and with two copies out, and on the borrower's
page; a return, and the card or the line gone; "Undo" tapped on the
Library screen after Back, and the loan out again; the bar gone by itself
after its time, and gone at once at a lock; a locked vault's item page
with no line and no name, and the line back after the unlock; "Not
returned" with its question; the Edit borrower form without loans; the
guide. With the font at its largest the words of the button take one line
on all three screens at the emulator's width (411 dp), and on the item's
page and the borrower's page at 320 dp too; on the loan card at 320 dp
they take two. The device's log held no error and no line with a name, a
title or a sentence of the bar. Not tried: a screen reader (the emulator
has none installed). On a phone with Android 14, in a debug build: looked
at and accepted by the maintainer; which points of the look were made was
not said. A save in the vault took 3 to 4 seconds there. A debug build
makes the vault's key step about 14 times slower than a release build
(measured on a Mac); a release build was not timed on the phone.
