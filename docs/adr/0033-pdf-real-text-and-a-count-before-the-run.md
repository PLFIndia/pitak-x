# ADR 0033: A PDF writes real text where no shaping is needed, and is counted before it is made

- **Status:** Accepted
- **Date:** 2026-11-25

## Context

The PDF export draws a library list with the `pdf` package. That
package puts one glyph after the other and does no SHAPING. For
Devanagari, Tamil and many other scripts that is not enough: letters
join, change form or change places, and only a text engine gets that
right. Until now the app therefore let Flutter's engine draw EVERY
piece of text and embedded it as a picture, Latin letters and digits
too. The review of November 2026 lists what follows as finding P3-B2:
memory grows with every row until the file is saved, "the export runs
for minutes with a progress bar and then the app closes".

What was read, measured and looked at BEFORE the design was final
(`PLAN.md`, D206 and D208):

- **The package** (`pdf` 3.13.1). A picture that was decoded is TWO
  "stream objects" of the document: the pixels, and their
  transparency. A page's content and an embedded font are stream
  objects too. Each keeps a buffer that starts at 64 KiB, and nothing
  leaves the document before the file is written. `save()` hands the
  writing to another isolate, and the whole document is copied to get
  there.
- **The Dart VM** (its source at tag 3.12.2, the app's version). In
  the app's Android build ("compressed pointers") the whole Dart heap
  lies in one region of 4 GB. A piece of memory of 64 KiB or more
  gets a place of its own there, 512 KiB wide: 8,192 places and no
  more. The package's buffer is just over that line.
- **So the limit is a COUNT, not a size.** A document can have about
  8,000 stream objects while it is built, however little each holds,
  on a strong phone as on a weak one.
- **On a phone** (Android 14, 7.7 GB of memory, a release build,
  10,000 made-up books): the bar stopped at about 2,020 books after
  48 seconds, and the page said "Export failed." The app stayed open.
  By the same arithmetic a library with its own titles, authors and
  ISBNs would have stopped at about 1,000 books (not run).

A prediction that was wrong, and what it changed: the review, and the
plan's first measurement on a Mac, expected gigabytes of memory and an
app that closes. The Mac's engine has no such region and could not
show the limit; the phone did. That is why this decision counts
objects and not bytes.

No other project's code was adapted. What the design rests on is the
package's and the VM's own source, read at the versions the app is
locked to, and trials outside the repository.

## Decision

1. **Real text where no shaping is needed** (D208). A text is "plain"
   when EVERY character of it is on an allow-list
   (`domain/pdf_plain_text.dart`): ASCII; Latin-1 without the soft
   hyphen, and Latin Extended-A and B; dashes, quotation marks,
   bullets and the ellipsis; per mille and primes; currency signs. A
   plain text is written as real text when the document's font also
   has a glyph for each of its characters. Every other text stays a
   picture, exactly as before: every Indian script, Arabic and Hebrew,
   a mark that combines, an emoji, and Greek and Cyrillic too (no need
   was shown; a range is one line and its tests). One character off
   the list makes the WHOLE text a picture, because a text is drawn in
   one piece. The list allows on purpose: a character nobody thought
   of costs a picture, never a wrongly drawn word. Not chosen: only a
   limit with a sentence; cheaper pictures in the same piece of work;
   Android's own PDF writer (see "Consequences").

2. **The fonts are the two Latin faces the app already bundles**
   (`NotoSans-Regular.ttf`, `NotoSans-Bold.ttf`), loaded for a PDF
   only (`pdfTextFontsLoader`). The package embeds only the glyphs
   that were used. The Indian faces are NOT given to the package as
   fonts: it could not shape them.

3. **A text is never left out silently, and never drawn wrongly.** A
   text that needs a picture and gets none (no rasterizer, no answer,
   bytes that are no picture) ends the export
   (`PdfTextPictureMissing`, which carries no text: a title is the
   user's data). Before, such a text fell to a built-in font and the
   run failed by accident; with a real font fed, a title could have
   been MISSING from a finished PDF. A logo or a footer icon that
   cannot be decoded is still skipped; an out-of-memory error is
   passed on from there.

4. **A PDF is counted before it is made** (D209). The renderer goes
   over the rows once WITHOUT drawing and counts the stream objects
   the document will have (`LibraryPdfRenderer.measure`,
   `infrastructure/pdf_object_count.dart`): one for a page, two for a
   picture of a text, two for a TrueType font, two for the logo and
   two for the footer icon as PNG (one as JPEG), one for the file. It
   is the SAME pass as the drawing (`PdfLibraryPass`, with `draw:
   false`): the same wrapping, the same page breaks, the same
   questions to the cache of pictures. So the count cannot drift from
   the drawing, and tests hold it to the finished file's own number
   of objects. A list that does not fit is refused before any picture
   is made (`PdfTooLargeFailure`, with the list's books and how many
   fit). Not chosen: a PDF of the books that fit (a catalogue with
   its end missing looks complete; Cancel was decided the same way);
   several PDFs for one list (the page hands over one file).

5. **The budget is 7,000 stream objects** (D214, D215), in ONE place
   (`pdfStreamObjectBudget`), with its reason beside it. A test holds
   the number a second time, so changing it is a decision. The rest
   of the app lives in the same region, so a document cannot have all
   8,192 places. Where a document really stops was looked for on
   devices first: a debug build in an emulator with 2 GB of memory
   saved a PDF of 7,661 objects and ran out of places between 7,758
   and about 7,960; the release build of before ran out at about
   8,090 on the phone.

6. **The file is written without the copy**: `PdfDocument.write` with
   `enableEventLoopBalancing`, not `save()`. With `save()` every
   buffer would be needed a second time. Measured with the app's
   renderer in plain Dart on a Mac (4,028 objects): `save()` grew the
   process by about 610 MB and held the calling isolate for up to
   0.2 s; `write` grows it by about 280 MB and lets the event loop
   turn every few milliseconds, so the progress row keeps moving. No
   test that RUNS can tell the two apart (under `flutter test` the
   package never leaves the calling isolate). A test that reads the
   source therefore keeps `.save` out of every file under `lib/` that
   imports the package
   (`test/architecture/pdf_document_write_test.dart`).

7. **Two endings get a sentence of their own** (D212, D213). Both are
   drawn as failures, brought into view and given to a screen reader
   to read, as every result on the Export page is (ADR 0032):
   - the list does not fit: "This list is too long for one PDF: it
     has N books, and about M fit. Titles and names in scripts such
     as Devanagari or Tamil are drawn as pictures, and a PDF can hold
     only so many. Narrow the list under "Books to include", choose
     fewer columns, or export CSV instead. Nothing was exported.";
   - the run ran out of memory all the same (the safety net under
     the count): "This phone ran out of memory for the PDF. Nothing
     was exported. Narrow the list under "Books to include", or
     export CSV instead." It is said for a PDF only, and only while
     the file has not been handed to the save window or the share
     sheet.

   Everything else stays "Export failed."

## Consequences

- A catalogue in Latin letters is no longer bounded by this: its rows
  cost pages only. On the phone the 10,000 made-up books are a PDF of
  264 pages and 271 objects, about a second after the tap (before:
  "Export failed." after 48 seconds).
- Latin text and digits of a PDF can now be selected, searched and
  copied, as a reader expects of a PDF. Text that is a picture
  cannot.
- A text in a script that needs shaping still costs two objects, so
  a library in such a script still has a limit: about 1,740 books
  when title and author are both such text and the columns are the
  default five, fewer with more such columns. What changed is that
  the app says so BEFORE the run, with how many books fit, in under a
  second. **This is not solved.** Two ways are left for a later
  decision (not chosen in D208, neither tried): one object for a
  picture instead of two (a picture without a second object for its
  transparency; about twice the books), and Android's own PDF writer,
  which shapes every script as real text (Android only; the drawing
  would move to Kotlin).
- Real text is drawn without kerning. Next to a picture of shaped
  text on the same row it looks a little lighter.
- A text that mixes scripts ("Godan गोदान") is a picture as a whole.
- The count rests on how many objects the package makes for a page, a
  picture, a font and a file. Each number is held to the finished
  file's own count by a test: a package update that changes one fails
  there.
- New code that makes a PDF writes it with `write`; the gate fails a
  `.save`.
- Known limits:
  - the budget is a count of places. No number covers a phone's own
    memory: at the budget a document takes about 580 MB of it at its
    most (measured on the phone: about 85 KiB an object), and a weak
    phone with other apps open could close the app with no sentence
    at all. That was not seen, and nothing that was tried was a weak
    phone;
  - the budget counts the document's objects. What else of the app
    lies in the region changes with the size of the library (seen
    with up to 13,500 books);
  - the page hears nothing while the count runs (under a second for
    13,500 books on the phone), and Cancel is not asked while the
    file is written, as before;
  - the file's objects are now compressed on the app's main isolate,
    in slices of about 4 ms. Another isolate did that before, after a
    copy that held the main isolate for longer;
  - iOS and desktop were not looked at (Android is the only target).

Looked at before it was accepted. In an emulator of API 36 with 2 GB
of memory, by the agent, in debug builds with a made-up library of
up to 3,650 books in Devanagari: with the budget taken out of the way
in one trial build, a run of all books ended with the "out of memory"
sentence, the app open and usable, and lists of 1,750 and of 1,900
books were saved (7,057 and 7,661 objects); with the real budget, all
books were refused within a second with "about 1736 fit", a list of
1,900 was refused through "Share file" with no share sheet, and 1,500
books were saved (6,048 objects, 88 seconds); the long sentence at
the largest font and 320 dp wide took 14 lines and was brought into
view whole. On a phone with Android 14, by the agent with the
maintainer's yes for each step, in a release build over an install
with 10,000 made-up books: all 10,000 saved about a second after the
tap; then, with 3,500 made-up books in Devanagari imported, 1,500 of
them saved after about 42 seconds (6,048 objects; the app's memory
grew by about 500 MB and was back within seconds), and all 13,500
refused within a second with "about 11671 fit", which is the budget
to the book. The saved files were opened on a Mac: every row of the
first is text that a search finds. Not tried: a weak phone; a screen
reader saying either sentence (tests hold that each is the page's
one live region); the largest font on the phone; the "out of memory"
sentence on a phone; a library of real books; the PDFs opened on the
phone itself.
